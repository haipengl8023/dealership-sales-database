BEGIN;
SET LOCAL search_path = dealership, pg_catalog;

INSERT INTO vehicle VALUES
    ('DEMO-NEW-001', 'Orion', 'Atlas', 2024, 40, 28000, false),
    ('DEMO-USED-001', 'Rivermark', 'Summit', 2021, 54200, 17500, true);

INSERT INTO customer VALUES ('buyer-01', 'Demo Buyer');
INSERT INTO salesperson VALUES ('rep-01', 'Demo Sales Representative', 0.05);
INSERT INTO test_drive (customer_id, vin, salesperson_id, scheduled_at)
VALUES ('buyer-01', 'DEMO-NEW-001', 'rep-01', '2025-01-04 10:00:00+11');

INSERT INTO sales_agreement VALUES
    ('sale-01', 'buyer-01', 'DEMO-NEW-001', '2025-01-04', 28000, 1000),
    ('sale-02', 'buyer-01', 'DEMO-USED-001', '2025-01-06', 17500, 0);

INSERT INTO aftermarket_option VALUES ('cargo', 'Cargo liner');
INSERT INTO purchased_aftermarket_option (vin, option_id, slot, price)
VALUES ('DEMO-NEW-001', 'cargo', 1, 450);
INSERT INTO trade_in_assessment VALUES ('sale-01', 'good', 'fair', 3000);

WITH finance_payment AS (
    INSERT INTO payment (agreement_id, method, amount, received_on)
    VALUES ('sale-01', 'finance', 20000, '2025-01-04')
    RETURNING payment_id
)
INSERT INTO bank_finance (agreement_id, payment_id, lender, term_months, annual_rate, loan_amount)
SELECT 'sale-01', payment_id, 'Demo Lender', 36, 6.25, 20000 FROM finance_payment;

INSERT INTO payment (agreement_id, method, amount, received_on)
VALUES ('sale-01', 'transfer', 4450, '2025-01-04');

COMMIT;
