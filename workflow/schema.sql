BEGIN;

CREATE SCHEMA dealership;
SET LOCAL search_path = dealership, pg_catalog;

CREATE TABLE vehicle (
    vin text PRIMARY KEY,
    make text NOT NULL,
    model text NOT NULL,
    build_year integer NOT NULL CHECK (build_year >= 1950),
    odometer_km integer NOT NULL CHECK (odometer_km >= 0),
    listed_price numeric(12, 2) NOT NULL CHECK (listed_price >= 0),
    is_preowned boolean NOT NULL,
    UNIQUE (vin, is_preowned)
);

CREATE TABLE customer (
    customer_id text PRIMARY KEY,
    display_name text NOT NULL
);

CREATE TABLE salesperson (
    salesperson_id text PRIMARY KEY,
    display_name text NOT NULL,
    commission_rate numeric(5, 4) NOT NULL CHECK (commission_rate BETWEEN 0 AND 0.10)
);

CREATE TABLE test_drive (
    test_drive_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id text NOT NULL REFERENCES customer,
    vin text NOT NULL REFERENCES vehicle,
    salesperson_id text NOT NULL REFERENCES salesperson,
    scheduled_at timestamptz NOT NULL,
    feedback text
);

CREATE TABLE sales_agreement (
    agreement_id text PRIMARY KEY,
    customer_id text NOT NULL REFERENCES customer,
    vin text NOT NULL UNIQUE REFERENCES vehicle,
    agreed_on date NOT NULL,
    base_price numeric(12, 2) NOT NULL CHECK (base_price >= 0),
    discount numeric(12, 2) NOT NULL DEFAULT 0 CHECK (discount BETWEEN 0 AND base_price)
);

CREATE TABLE trade_in_assessment (
    agreement_id text PRIMARY KEY REFERENCES sales_agreement,
    mechanical_condition text NOT NULL CHECK (mechanical_condition IN ('poor', 'fair', 'good', 'excellent')),
    body_condition text NOT NULL CHECK (body_condition IN ('poor', 'fair', 'good', 'excellent')),
    assessed_value numeric(12, 2) NOT NULL CHECK (assessed_value > 0)
);

CREATE TABLE aftermarket_option (
    option_id text PRIMARY KEY,
    name text NOT NULL
);

CREATE TABLE purchased_aftermarket_option (
    vin text,
    option_id text REFERENCES aftermarket_option,
    slot smallint NOT NULL CHECK (slot BETWEEN 1 AND 8),
    price numeric(12, 2) NOT NULL CHECK (price >= 0),
    vehicle_is_preowned boolean GENERATED ALWAYS AS (false) STORED,
    PRIMARY KEY (vin, option_id),
    UNIQUE (vin, slot),
    FOREIGN KEY (vin, vehicle_is_preowned) REFERENCES vehicle (vin, is_preowned)
);

CREATE FUNCTION check_option_vehicle()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = dealership, pg_catalog
AS $$
DECLARE
    preowned boolean;
BEGIN
    -- The foreign key also enforces this rule across concurrent changes.
    SELECT is_preowned INTO preowned FROM vehicle WHERE vin = NEW.vin;
    IF preowned THEN
        RAISE check_violation USING MESSAGE = 'Aftermarket options require a new vehicle.';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER validate_option_vehicle
BEFORE INSERT OR UPDATE OF vin ON purchased_aftermarket_option
FOR EACH ROW EXECUTE FUNCTION check_option_vehicle();

CREATE TABLE payment (
    payment_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    agreement_id text NOT NULL REFERENCES sales_agreement,
    method text NOT NULL CHECK (method IN ('card', 'transfer', 'finance')),
    amount numeric(12, 2) NOT NULL CHECK (amount > 0),
    received_on date NOT NULL,
    UNIQUE (payment_id, agreement_id)
);

CREATE TABLE bank_finance (
    agreement_id text PRIMARY KEY REFERENCES sales_agreement,
    payment_id bigint NOT NULL UNIQUE,
    lender text NOT NULL,
    term_months integer NOT NULL CHECK (term_months BETWEEN 12 AND 50),
    annual_rate numeric(6, 3) NOT NULL CHECK (annual_rate > 0),
    loan_amount numeric(12, 2) NOT NULL CHECK (loan_amount > 0),
    FOREIGN KEY (payment_id, agreement_id) REFERENCES payment (payment_id, agreement_id)
);

CREATE VIEW agreement_balance AS
WITH option_totals AS (
    SELECT vin, sum(price) AS options_total FROM purchased_aftermarket_option GROUP BY vin
),
payment_totals AS (
    SELECT agreement_id, sum(amount) AS paid_total FROM payment GROUP BY agreement_id
),
prices AS (
    SELECT a.agreement_id, a.vin, a.base_price, a.discount,
           coalesce(o.options_total, 0) AS options_total,
           coalesce(t.assessed_value, 0) AS trade_in_value,
           a.base_price - a.discount + coalesce(o.options_total, 0) - coalesce(t.assessed_value, 0) AS final_price,
           coalesce(p.paid_total, 0) AS paid_total
    FROM sales_agreement a
    LEFT JOIN option_totals o USING (vin)
    LEFT JOIN trade_in_assessment t USING (agreement_id)
    LEFT JOIN payment_totals p USING (agreement_id)
)
SELECT prices.*, final_price - paid_total AS balance_due,
       CASE
           WHEN paid_total > final_price THEN 'overpaid'
           WHEN paid_total = final_price THEN 'completed'
           ELSE 'pending'
       END AS sale_status
FROM prices;

COMMIT;
