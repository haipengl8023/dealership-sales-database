BEGIN;
SET LOCAL plpgsql.check_asserts = on;

DO $$
DECLARE
    balance record;
    finance_payment_id bigint;
BEGIN
    SELECT * INTO STRICT balance FROM dealership.agreement_balance WHERE agreement_id = 'sale-01';
    ASSERT balance.final_price = 24450 AND balance.balance_due = 0
        AND balance.sale_status = 'completed', 'Initial agreement must reconcile.';

    UPDATE dealership.trade_in_assessment SET assessed_value = 2500 WHERE agreement_id = 'sale-01';
    SELECT * INTO STRICT balance FROM dealership.agreement_balance WHERE agreement_id = 'sale-01';
    ASSERT balance.final_price = 24950 AND balance.balance_due = 500
        AND balance.sale_status = 'pending', 'Trade-in changes must refresh the balance.';

    UPDATE dealership.trade_in_assessment SET assessed_value = 3200 WHERE agreement_id = 'sale-01';
    SELECT * INTO STRICT balance FROM dealership.agreement_balance WHERE agreement_id = 'sale-01';
    ASSERT balance.balance_due = -200 AND balance.sale_status = 'overpaid', 'Overpayments must be visible.';

    DELETE FROM dealership.payment WHERE agreement_id = 'sale-01' AND method = 'transfer';
    SELECT * INTO STRICT balance FROM dealership.agreement_balance WHERE agreement_id = 'sale-01';
    ASSERT balance.paid_total = 20000 AND balance.sale_status = 'pending', 'Payment deletion must reopen the balance.';

    BEGIN
        INSERT INTO dealership.purchased_aftermarket_option (vin, option_id, slot, price)
        VALUES ('DEMO-USED-001', 'cargo', 1, 450);
        RAISE EXCEPTION 'Expected the pre-owned option insert to fail.';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    BEGIN
        UPDATE dealership.vehicle SET is_preowned = true WHERE vin = 'DEMO-NEW-001';
        RAISE EXCEPTION 'Expected the condition change to fail while options exist.';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;

    INSERT INTO dealership.aftermarket_option
    SELECT 'test-option-' || i, 'Synthetic test option ' || i FROM generate_series(2, 9) i;
    INSERT INTO dealership.purchased_aftermarket_option (vin, option_id, slot, price)
    SELECT 'DEMO-NEW-001', 'test-option-' || i, i, 100 FROM generate_series(2, 8) i;

    SELECT * INTO STRICT balance FROM dealership.agreement_balance WHERE agreement_id = 'sale-01';
    ASSERT balance.options_total = 1150 AND balance.paid_total = 20000,
        'Option and payment totals must be aggregated separately.';

    BEGIN
        INSERT INTO dealership.purchased_aftermarket_option (vin, option_id, slot, price)
        VALUES ('DEMO-NEW-001', 'test-option-9', 9, 100);
        RAISE EXCEPTION 'Expected the ninth option to fail.';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO dealership.purchased_aftermarket_option (vin, option_id, slot, price)
        VALUES ('DEMO-NEW-001', 'test-option-9', 8, 100);
        RAISE EXCEPTION 'Expected reuse of an occupied slot to fail.';
    EXCEPTION WHEN unique_violation THEN
        NULL;
    END;

    INSERT INTO dealership.payment (agreement_id, method, amount, received_on)
    VALUES ('sale-02', 'finance', 5000, '2025-01-06') RETURNING payment_id INTO finance_payment_id;

    DELETE FROM dealership.bank_finance WHERE agreement_id = 'sale-01';
    BEGIN
        INSERT INTO dealership.bank_finance
        VALUES ('sale-01', finance_payment_id, 'Demo Lender', 24, 5.5, 5000);
        RAISE EXCEPTION 'Expected cross-agreement financing to fail.';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;
END;
$$;

DO $$
DECLARE
    summary record;
    sale_id bigint;
BEGIN
    SELECT * INTO STRICT summary FROM sales_reporting.get_car_sales_summary()
    WHERE make = 'Orion' AND model = 'Atlas';
    ASSERT summary.available_units = 1 AND summary.sold_units = 2
        AND summary.total_sales = 54450 AND summary.last_purchased_at = DATE '2025-01-03',
        'Atlas counts, revenue and chronological latest sale must reconcile.';

    SELECT * INTO STRICT summary FROM sales_reporting.get_car_sales_summary()
    WHERE make = 'Orion' AND model = 'Orbit';
    ASSERT summary.available_units = 0 AND summary.sold_units = 0
        AND summary.total_sales = 0 AND summary.last_purchased_at IS NULL,
        'Models without inventory must remain visible.';

    BEGIN
        PERFORM sales_reporting.add_car_sale('Rivermark', 'Atlas', 2024, 0, 24000);
        RAISE EXCEPTION 'Expected a make and model mismatch to fail.';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;

    sale_id := sales_reporting.add_car_sale('orion', 'ATLAS', 2024, 0, 24000);
    BEGIN
        PERFORM sales_reporting.record_car_sale(sale_id, 'buyer-01', 'rep-01', CURRENT_DATE + 1);
        RAISE EXCEPTION 'Expected a future sale date to fail.';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    ASSERT sales_reporting.record_car_sale(sale_id, 'buyer-01', 'rep-01', DATE '2025-01-08'),
        'An available vehicle must be sellable.';
    ASSERT NOT sales_reporting.record_car_sale(sale_id, 'buyer-01', 'rep-01', DATE '2025-01-09'),
        'A completed sale must stay unchanged on retry.';

    SELECT * INTO STRICT summary FROM sales_reporting.get_car_sales_summary()
    WHERE make = 'Orion' AND model = 'Atlas';
    ASSERT summary.available_units = 1 AND summary.sold_units = 3
        AND summary.total_sales = 78450 AND summary.last_purchased_at = DATE '2025-01-08',
        'The completed sale must be reflected in the summary.';
END;
$$;

ROLLBACK;
\echo Both PostgreSQL modules passed.
