BEGIN;

CREATE SCHEMA sales_reporting;
SET LOCAL search_path = sales_reporting, pg_catalog;

CREATE TABLE make (
    make_id text PRIMARY KEY,
    name text NOT NULL
);
CREATE UNIQUE INDEX make_name_ci ON make (lower(name));

CREATE TABLE model (
    model_id text PRIMARY KEY,
    make_id text NOT NULL REFERENCES make,
    name text NOT NULL
);
CREATE UNIQUE INDEX model_name_per_make_ci ON model (make_id, lower(name));

CREATE TABLE customer (
    customer_id text PRIMARY KEY,
    display_name text NOT NULL
);

CREATE TABLE salesperson (
    salesperson_id text PRIMARY KEY,
    display_name text NOT NULL
);

CREATE TABLE car_sale (
    car_sale_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    model_id text NOT NULL REFERENCES model,
    built_year integer NOT NULL CHECK (built_year BETWEEN 1950 AND extract(year FROM CURRENT_DATE)),
    odometer_km integer NOT NULL CHECK (odometer_km >= 0),
    price numeric(12, 2) NOT NULL CHECK (price > 0),
    customer_id text REFERENCES customer,
    salesperson_id text REFERENCES salesperson,
    sold_on date CHECK (sold_on <= CURRENT_DATE),
    CHECK (
        (customer_id IS NULL AND salesperson_id IS NULL AND sold_on IS NULL)
        OR (customer_id IS NOT NULL AND salesperson_id IS NOT NULL AND sold_on IS NOT NULL)
    )
);
CREATE INDEX car_sale_model ON car_sale (model_id);

CREATE FUNCTION add_car_sale(
    make_name text, model_name text, build_year integer, odometer integer, asking_price numeric
)
RETURNS bigint
LANGUAGE plpgsql
SET search_path = sales_reporting, pg_catalog
AS $$
DECLARE
    selected_model text;
    created_sale bigint;
BEGIN
    SELECT mo.model_id INTO selected_model
    FROM model mo JOIN make ma USING (make_id)
    WHERE lower(ma.name) = lower(make_name) AND lower(mo.name) = lower(model_name);

    IF NOT FOUND THEN
        RAISE foreign_key_violation USING MESSAGE = 'The make and model combination does not exist.';
    END IF;

    INSERT INTO car_sale (model_id, built_year, odometer_km, price)
    VALUES (selected_model, build_year, odometer, asking_price)
    RETURNING car_sale_id INTO created_sale;
    RETURN created_sale;
END;
$$;

CREATE FUNCTION record_car_sale(sale_id bigint, buyer text, seller text, sale_date date)
RETURNS boolean
LANGUAGE plpgsql
SET search_path = sales_reporting, pg_catalog
AS $$
BEGIN
    IF buyer IS NULL OR seller IS NULL OR sale_date IS NULL THEN
        RAISE not_null_violation USING MESSAGE = 'A completed sale requires a buyer, salesperson and date.';
    END IF;

    UPDATE car_sale
    SET customer_id = buyer, salesperson_id = seller, sold_on = sale_date
    WHERE car_sale_id = sale_id AND sold_on IS NULL;
    RETURN FOUND;
END;
$$;

CREATE FUNCTION get_car_sales_summary()
RETURNS TABLE (
    make text,
    model text,
    available_units bigint,
    sold_units bigint,
    total_sales numeric,
    last_purchased_at date
)
LANGUAGE sql STABLE
SET search_path = sales_reporting, pg_catalog
AS $$
    SELECT ma.name, mo.name,
           count(cs.car_sale_id) FILTER (WHERE cs.sold_on IS NULL),
           count(cs.car_sale_id) FILTER (WHERE cs.sold_on IS NOT NULL),
           coalesce(sum(cs.price) FILTER (WHERE cs.sold_on IS NOT NULL), 0),
           max(cs.sold_on)
    FROM make ma
    JOIN model mo USING (make_id)
    LEFT JOIN car_sale cs USING (model_id)
    GROUP BY ma.make_id, mo.model_id
    ORDER BY ma.name, mo.name;
$$;

COMMIT;
