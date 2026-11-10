BEGIN;
SET LOCAL search_path = sales_reporting, pg_catalog;

INSERT INTO make VALUES ('orion', 'Orion'), ('river', 'Rivermark');
INSERT INTO model VALUES
    ('atlas', 'orion', 'Atlas'),
    ('orbit', 'orion', 'Orbit'),
    ('summit', 'river', 'Summit');
INSERT INTO customer VALUES ('buyer-01', 'Demo Buyer');
INSERT INTO salesperson VALUES ('rep-01', 'Demo Sales Representative');

INSERT INTO car_sale (model_id, built_year, odometer_km, price, customer_id, salesperson_id, sold_on) VALUES
    ('atlas', 2023, 21000, 26000, 'buyer-01', 'rep-01', '2024-12-31'),
    ('atlas', 2024, 14000, 28450, 'buyer-01', 'rep-01', '2025-01-03'),
    ('atlas', 2024, 12000, 29000, NULL, NULL, NULL),
    ('summit', 2022, 49000, 19500, NULL, NULL, NULL);

COMMIT;
