import os
import json
import requests
import psycopg2
from datetime import datetime, timezone
from dotenv import load_dotenv
from pathlib import Path
load_dotenv()


PROJECT_ROOT = Path(__file__).resolve().parents[1]
load_dotenv(PROJECT_ROOT / ".env")

API_URL = "https://pos.open.nhanh.vn/v3.0/product/category"

APP_ID = os.getenv("NHANH_APP_ID")
BUSINESS_ID = os.getenv("NHANH_BUSINESS_ID")
ACCESS_TOKEN = os.getenv("NHANH_ACCESS_TOKEN")

DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = int(os.getenv("DB_PORT", "5432"))
DB_NAME = os.getenv("DB_NAME", "data_center")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD")

def main():
    required = {
    "NHANH_APP_ID": APP_ID,
    "NHANH_BUSINESS_ID": BUSINESS_ID,
    "NHANH_ACCESS_TOKEN": ACCESS_TOKEN,
    "DB_PASSWORD": DB_PASSWORD,
    }

    missing = [name for name, value in required.items() if not value]

    if missing:
        raise RuntimeError(
        f"Missing environment variables: {', '.join(missing)}"
    )

    categories = {}
    next_page = None
    seen_cursors = set()

    while True:
        body = {
            "filters": {},
            "paginator": {"size": 100}
        }

        if next_page is not None:
            body["paginator"]["next"] = next_page

        response = requests.post(
            API_URL,
            params={"appId": APP_ID, "businessId": BUSINESS_ID},
            headers={
                "Authorization": ACCESS_TOKEN,
                "Content-Type": "application/json"
            },
            json=body,
            timeout=60
        )
        response.raise_for_status()

        result = response.json()

        if result.get("code") != 1:
            raise RuntimeError(f"Nhanh API error: {result}")

        rows = result.get("data", [])

        for row in rows:
            categories[int(row["id"])] = row

        next_page = result.get("paginator", {}).get("next")

        print(f"Fetched {len(rows)} categories")

        if not next_page:
            break

        cursor_key = json.dumps(next_page, sort_keys=True)

        if cursor_key in seen_cursors:
            raise RuntimeError("Repeated pagination cursor")

        seen_cursors.add(cursor_key)

    with psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD
) as conn:
        with conn.cursor() as cur:
            for category_id, row in categories.items():
                cur.execute(
                    """
                    INSERT INTO raw.nhanh_categories (
                        category_id,
                        api_response
                    )
                    VALUES (%s, %s::jsonb)
                    ON CONFLICT (category_id)
                    DO UPDATE SET
                        api_response = EXCLUDED.api_response,
                        last_ingested_at = NOW()
                    """,
                    (category_id, json.dumps(row, ensure_ascii=False))
                )

    print(f"SUCCESS: {len(categories)} categories synchronized")


if __name__ == "__main__":
    main()