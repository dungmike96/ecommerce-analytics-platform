
import os
import json
import hashlib
import logging
from pathlib import Path
from datetime import datetime, timezone

import gspread
import psycopg2
from psycopg2.extras import Json, execute_values
from google.oauth2.service_account import Credentials
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]
load_dotenv(ROOT / ".env")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s"
)

KEY_FILE = ROOT / "secrets" / "sheets_service_account.json"
SPREADSHEET_ID = os.environ["GOOGLE_SHEETS_EXPENSES_ID"]
SHEET_NAME = "CHI TIỀN"

HEADERS = [
    "Nghiệp vụ", "Ngày tháng", "Chứng từ",
    "Diễn giải", "Số tiền",
    "Khách hàng-Nhà cung cấp",
    "CHI", "THU", "Người nhận tiền",
    "Địa chỉ", "Loại Chi"
]

def main():
    credentials = Credentials.from_service_account_file(
        str(KEY_FILE),
        scopes=[
            "https://www.googleapis.com/auth/spreadsheets.readonly"
        ]
    )

    client = gspread.authorize(credentials)
    sheet = client.open_by_key(
        SPREADSHEET_ID
    ).worksheet(SHEET_NAME)

    # Lấy giá trị hiển thị, giữ nguyên định dạng nguồn
    rows = sheet.get_all_values()

    if not rows or rows[0][:11] != HEADERS:
        raise ValueError(
            "Google Sheets header mismatch. Aborting."
        )

    records = []

    for row_number, row in enumerate(rows[1:], start=2):
        values = (row + [""] * 11)[:11]

        if not any(str(v).strip() for v in values):
            continue

        row_data = dict(zip(HEADERS, values))

        row_hash = hashlib.sha256(
            json.dumps(
                row_data,
                ensure_ascii=False,
                sort_keys=True
            ).encode("utf-8")
        ).hexdigest()

        records.append((
            SPREADSHEET_ID,
            SHEET_NAME,
            row_number,
            Json(row_data),
            row_hash
        ))

    logging.info("Fetched %s populated rows", len(records))

    # Chặn đồng bộ rỗng ngoài ý muốn
    if not records:
        raise ValueError("No data found. Aborting.")

    
    conn = psycopg2.connect(
        host=os.getenv("DB_HOST", "localhost"),
        port=os.getenv("DB_PORT", "5432"),
        dbname=os.getenv("DB_NAME", "data_center"),
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"]
    )


    try:
        with conn:
            with conn.cursor() as cur:
                # Full snapshot, transaction đảm bảo rollback
                # nếu ghi dữ liệu thất bại
                cur.execute("""
                    DELETE FROM raw.google_sheets_expenses
                    WHERE spreadsheet_id = %s
                      AND sheet_name = %s
                """, (SPREADSHEET_ID, SHEET_NAME))

                execute_values(
                    cur,
                    """
                    INSERT INTO raw.google_sheets_expenses (
                        spreadsheet_id,
                        sheet_name,
                        source_row_number,
                        row_data,
                        row_hash
                    )
                    VALUES %s
                    """,
                    records,
                    page_size=500
                )

        logging.info(
            "SUCCESS | Loaded %s rows into RAW",
            len(records)
        )

    finally:
        conn.close()

if __name__ == "__main__":
    main()
