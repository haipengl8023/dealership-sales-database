"""PostgreSQL access for the sales reporting schema."""

import json
from contextlib import closing
from datetime import date
from decimal import Decimal

import psycopg2
from psycopg2.extensions import connection
from psycopg2.extras import RealDictCursor


def open_connection() -> connection:
    """Read the connection settings from libpq's PG environment variables."""
    return psycopg2.connect(connect_timeout=5)


def get_car_sales_summary(conn: connection) -> list[dict]:
    with conn.cursor(cursor_factory=RealDictCursor) as cursor:
        cursor.execute("SELECT * FROM sales_reporting.get_car_sales_summary() ORDER BY make, model")
        return [dict(row) for row in cursor.fetchall()]


def find_car_sales(conn: connection, query: str) -> list[dict]:
    """Search by make, model, buyer or salesperson using literal text."""
    with conn.cursor(cursor_factory=RealDictCursor) as cursor:
        cursor.execute(
            """
            SELECT cs.car_sale_id, ma.name AS make, mo.name AS model, cs.built_year,
                   cs.odometer_km, cs.price, cs.sold_on,
                   cu.display_name AS buyer, sp.display_name AS salesperson
            FROM sales_reporting.car_sale cs
            JOIN sales_reporting.model mo USING (model_id)
            JOIN sales_reporting.make ma USING (make_id)
            LEFT JOIN sales_reporting.customer cu USING (customer_id)
            LEFT JOIN sales_reporting.salesperson sp USING (salesperson_id)
            WHERE strpos(lower(concat_ws(' ', ma.name, mo.name, cu.display_name, sp.display_name)),
                         lower(%s)) > 0
            ORDER BY cs.sold_on DESC NULLS FIRST, cs.car_sale_id
            """,
            (query.strip(),),
        )
        return [dict(row) for row in cursor.fetchall()]


def add_car_sale(
    conn: connection, make: str, model: str, built_year: int, odometer_km: int, price: Decimal
) -> int:
    with conn.cursor() as cursor:
        cursor.execute(
            "SELECT sales_reporting.add_car_sale(%s, %s, %s, %s, %s)",
            (make, model, built_year, odometer_km, price),
        )
        return cursor.fetchone()[0]


def record_car_sale(
    conn: connection, sale_id: int, buyer_id: str, salesperson_id: str, sold_on: date
) -> bool:
    with conn.cursor() as cursor:
        cursor.execute(
            "SELECT sales_reporting.record_car_sale(%s, %s, %s, %s)",
            (sale_id, buyer_id, salesperson_id, sold_on),
        )
        return cursor.fetchone()[0]


if __name__ == "__main__":
    with closing(open_connection()) as db:
        print(json.dumps(get_car_sales_summary(db), default=str, indent=2))
