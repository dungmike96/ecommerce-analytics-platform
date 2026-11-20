import json
import logging
import os
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import psycopg2
import requests
from dotenv import load_dotenv
from psycopg2.extras import Json, execute_batch


# ============================================================
# 1. ENV
# ============================================================

PROJECT_ROOT = Path(__file__).resolve().parent.parent
ENV_FILE = PROJECT_ROOT / ".env"

if not ENV_FILE.exists():
    raise RuntimeError(
        f"Không tìm thấy file .env tại: {ENV_FILE}"
    )

load_dotenv(dotenv_path=ENV_FILE)


def required_env(name: str) -> str:
    value = os.getenv(name, "").strip()

    if (
        len(value) >= 2
        and value[0] == value[-1]
        and value[0] in {"'", '"'}
    ):
        value = value[1:-1].strip()

    if not value:
        raise RuntimeError(f"Thiếu biến môi trường: {name}")

    return value


def optional_int(name: str, default: int) -> int:
    value = os.getenv(name, "").strip()

    if not value:
        return default

    try:
        return int(value)
    except ValueError as exc:
        raise RuntimeError(
            f"{name} phải là số nguyên"
        ) from exc


# ============================================================
# 2. CONFIG
# ============================================================

APP_ID = required_env("NHANH_APP_ID")
BUSINESS_ID = required_env("NHANH_BUSINESS_ID")
ACCESS_TOKEN = required_env("NHANH_ACCESS_TOKEN")

if ACCESS_TOKEN.lower().startswith("bearer "):
    ACCESS_TOKEN = ACCESS_TOKEN[7:].strip()


DB_CONFIG = {
    "host": required_env("DB_HOST"),
    "port": optional_int("DB_PORT", 5432),
    "database": required_env("DB_NAME"),
    "user": required_env("DB_USER"),
    "password": required_env("DB_PASSWORD"),
}


API_URL = "https://pos.open.nhanh.vn/v3.0/customer/list"

PAGE_SIZE = min(
    optional_int("NHANH_PAGE_SIZE", 100),
    100,
)

HTTP_TIMEOUT = optional_int(
    "NHANH_HTTP_TIMEOUT",
    60,
)

MAX_RETRIES = optional_int(
    "NHANH_MAX_RETRIES",
    3,
)


# Việt Nam UTC+7
VN_TZ = timezone(timedelta(hours=7))


# ============================================================
# 3. LOGGING
# ============================================================

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)

logger = logging.getLogger("nhanh_customer_ingestion")


def mask_token(token: str) -> str:
    if len(token) <= 8:
        return "***"

    return f"{token[:4]}...{token[-4:]}"


# ============================================================
# 4. DATABASE
# ============================================================

def get_connection():
    return psycopg2.connect(**DB_CONFIG)


def initialize_database() -> None:

    sql = """
    CREATE SCHEMA IF NOT EXISTS raw;


    CREATE TABLE IF NOT EXISTS raw.nhanh_customers (

        customer_id BIGINT PRIMARY KEY,

        api_response JSONB NOT NULL,

        source_app_id TEXT NOT NULL,
        source_business_id TEXT NOT NULL,

        source_updated_at TIMESTAMPTZ,

        first_ingested_at TIMESTAMPTZ
            NOT NULL DEFAULT CURRENT_TIMESTAMP,

        last_ingested_at TIMESTAMPTZ
            NOT NULL DEFAULT CURRENT_TIMESTAMP
    );


    CREATE TABLE IF NOT EXISTS raw.ingestion_watermark (

        source_name TEXT PRIMARY KEY,

        last_updated_at BIGINT,

        updated_at TIMESTAMPTZ
            NOT NULL DEFAULT CURRENT_TIMESTAMP
    );


    CREATE INDEX IF NOT EXISTS
        idx_nhanh_customers_source_updated
    ON raw.nhanh_customers(source_updated_at);
    """

    conn = get_connection()

    try:
        with conn.cursor() as cur:
            cur.execute(sql)

        conn.commit()

    except Exception:
        conn.rollback()
        raise

    finally:
        conn.close()

    logger.info("Customer RAW database objects ready.")


# ============================================================
# 5. UNIX TIMESTAMP HELPERS
# ============================================================

def datetime_to_unix(dt: datetime) -> int:
    return int(dt.timestamp())


def unix_to_datetime(
    value: Optional[int]
) -> Optional[datetime]:

    if not value:
        return None

    try:
        value = int(value)

        if value <= 0:
            return None

        return datetime.fromtimestamp(
            value,
            tz=VN_TZ,
        )

    except (ValueError, TypeError, OSError):
        return None


# ============================================================
# 6. WATERMARK
# ============================================================

WATERMARK_NAME = "nhanh_customers_updated_at"


def get_watermark() -> Optional[int]:

    sql = """
        SELECT last_updated_at
        FROM raw.ingestion_watermark
        WHERE source_name = %s;
    """

    conn = get_connection()

    try:
        with conn.cursor() as cur:
            cur.execute(
                sql,
                (WATERMARK_NAME,),
            )

            row = cur.fetchone()

        if row and row[0]:
            return int(row[0])

        return None

    finally:
        conn.close()


def save_watermark(
    timestamp_value: int
) -> None:

    sql = """
        INSERT INTO raw.ingestion_watermark (
            source_name,
            last_updated_at,
            updated_at
        )

        VALUES (
            %s,
            %s,
            CURRENT_TIMESTAMP
        )

        ON CONFLICT (source_name)

        DO UPDATE SET
            last_updated_at =
                EXCLUDED.last_updated_at,

            updated_at =
                CURRENT_TIMESTAMP;
    """

    conn = get_connection()

    try:
        with conn.cursor() as cur:
            cur.execute(
                sql,
                (
                    WATERMARK_NAME,
                    timestamp_value,
                ),
            )

        conn.commit()

    except Exception:
        conn.rollback()
        raise

    finally:
        conn.close()


# ============================================================
# 7. HTTP
# ============================================================

SESSION = requests.Session()

SESSION.headers.update({
    "Authorization": ACCESS_TOKEN,
    "Content-Type": "application/json",
    "Accept": "application/json",
})


def call_nhanh_api(
    body: Dict[str, Any]
) -> Dict[str, Any]:

    params = {
        "appId": APP_ID,
        "businessId": BUSINESS_ID,
    }

    for attempt in range(
        1,
        MAX_RETRIES + 1,
    ):

        try:

            response = SESSION.post(
                API_URL,
                params=params,
                json=body,
                timeout=HTTP_TIMEOUT,
            )

        except requests.RequestException as exc:

            if attempt >= MAX_RETRIES:
                raise RuntimeError(
                    f"Không kết nối được Nhanh.vn: {exc}"
                ) from exc

            wait = 2 ** (attempt - 1)

            logger.warning(
                "Network error. Retry after %ss.",
                wait,
            )

            time.sleep(wait)
            continue


        try:
            payload = response.json()

        except ValueError as exc:

            raise RuntimeError(
                "Nhanh.vn trả response không phải JSON. "
                f"HTTP={response.status_code}, "
                f"response={response.text[:500]}"
            ) from exc


        if payload.get("code") == 1:
            return payload


        error_code = payload.get("errorCode")


        # Rate limit
        if (
            error_code
            in {
                "ERR_429",
                "ERR_EXCEEDED_RATE_LIMIT",
            }
            and attempt < MAX_RETRIES
        ):

            data = payload.get("data") or {}

            try:
                wait = max(
                    int(
                        data.get(
                            "lockedSeconds",
                            1,
                        )
                    ),
                    1,
                )

            except (ValueError, TypeError):
                wait = 1

            logger.warning(
                "Rate limit. Wait %ss.",
                wait,
            )

            time.sleep(wait)
            continue


        raise RuntimeError(
            "Nhanh Customer API error: "
            + json.dumps(
                payload,
                ensure_ascii=False,
                default=str,
            )
        )


    raise RuntimeError(
        "Nhanh Customer API failed after retries."
    )


# ============================================================
# 8. RESPONSE PARSER
# ============================================================

def parse_response(
    payload: Dict[str, Any]
) -> Tuple[
    List[Dict[str, Any]],
    Optional[Any],
]:

    data = payload.get("data") or []

    if not isinstance(data, list):
        raise RuntimeError(
            "Response data của Customer API "
            "không phải list như document."
        )

    customers = [
        item
        for item in data
        if isinstance(item, dict)
    ]

    paginator = (
        payload.get("paginator")
        or {}
    )

    next_cursor = (
        paginator.get("next")
        if isinstance(paginator, dict)
        else None
    )

    if next_cursor in (
        "",
        None,
        [],
        {},
    ):
        next_cursor = None

    return customers, next_cursor


# ============================================================
# 9. CUSTOMER FIELD HELPERS
# ============================================================

def get_customer_id(
    customer: Dict[str, Any]
) -> Optional[int]:

    value = customer.get("id")

    if value in (None, ""):
        return None

    try:
        return int(value)

    except (ValueError, TypeError):
        return None


# ============================================================
# 10. UPSERT
# ============================================================

def upsert_customers(
    customers: List[Dict[str, Any]]
) -> int:

    if not customers:
        return 0


    sql = """
    INSERT INTO raw.nhanh_customers (

        customer_id,

        api_response,

        source_app_id,
        source_business_id,

        source_updated_at,

        first_ingested_at,
        last_ingested_at
    )

    VALUES (
        %s,
        %s,
        %s,
        %s,
        %s,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
    )

    ON CONFLICT (customer_id)

    DO UPDATE SET

        api_response =
            EXCLUDED.api_response,

        source_app_id =
            EXCLUDED.source_app_id,

        source_business_id =
            EXCLUDED.source_business_id,

        source_updated_at =
            EXCLUDED.source_updated_at,

        last_ingested_at =
            CURRENT_TIMESTAMP;
    """


    rows = []


    for customer in customers:

        customer_id = get_customer_id(
            customer
        )

        if customer_id is None:

            logger.warning(
                "Skip customer without valid id"
            )

            continue


        updated_at = unix_to_datetime(
            customer.get("updatedAt")
        )


        rows.append(
            (
                customer_id,
                Json(customer),
                APP_ID,
                BUSINESS_ID,
                updated_at,
            )
        )


    if not rows:
        return 0


    conn = get_connection()

    try:

        with conn.cursor() as cur:

            execute_batch(
                cur,
                sql,
                rows,
                page_size=100,
            )

        conn.commit()

        return len(rows)

    except Exception:
        conn.rollback()
        raise

    finally:
        conn.close()


# ============================================================
# 11. FETCH CUSTOMER PAGES
# ============================================================

def fetch_customers(
    filters: Optional[Dict[str, Any]] = None
) -> Tuple[int, int]:

    next_cursor = None
    seen_cursors = set()

    pages = 0
    customers_received = 0


    while True:

        pages += 1


        paginator: Dict[str, Any] = {
            "size": PAGE_SIZE,
        }


        if next_cursor is not None:
            paginator["next"] = next_cursor


        body = {
            "filters": filters or {},
            "paginator": paginator,
        }


        logger.info(
            "CUSTOMER PAGE %s",
            pages,
        )


        payload = call_nhanh_api(body)

        customers, returned_next = (
            parse_response(payload)
        )


        logger.info(
            "Page %s received %s customers",
            pages,
            len(customers),
        )


        if customers:

            upserted = upsert_customers(
                customers
            )

            customers_received += len(
                customers
            )

            logger.info(
                "Upserted %s customers.",
                upserted,
            )


        if returned_next is None:
            break


        cursor_key = json.dumps(
            returned_next,
            sort_keys=True,
            default=str,
        )


        if cursor_key in seen_cursors:

            raise RuntimeError(
                "Customer paginator cursor lặp. "
                "Dừng để tránh infinite loop."
            )


        seen_cursors.add(
            cursor_key
        )

        next_cursor = returned_next


    return pages, customers_received


# ============================================================
# 12. INITIAL FULL LOAD
# ============================================================

def run_initial_full_load() -> None:

    logger.info(
        "CUSTOMER INITIAL FULL LOAD START"
    )


    # Ghi nhận thời điểm bắt đầu scan.
    #
    # Dùng thời điểm START thay vì END làm watermark
    # để tránh mất customer được update trong lúc
    # full scan đang chạy.
    scan_started_at = datetime.now(VN_TZ)

    scan_started_timestamp = (
        datetime_to_unix(scan_started_at)
    )


    pages, received = fetch_customers(
        filters={}
    )


    # Chỉ save watermark khi toàn bộ pagination
    # đã chạy thành công.
    save_watermark(
        scan_started_timestamp
    )


    logger.info(
        "CUSTOMER INITIAL FULL LOAD COMPLETE | "
        "pages=%s | API customers=%s | "
        "watermark=%s",
        pages,
        received,
        scan_started_timestamp,
    )


# ============================================================
# 13. INCREMENTAL UPDATED CUSTOMERS
# ============================================================

def run_incremental(
    watermark: int
) -> None:

    now = datetime.now(VN_TZ)

    to_timestamp = datetime_to_unix(
        now
    )


    # Overlap 5 phút để giảm nguy cơ mất
    # customer ở biên thời gian.
    overlap_seconds = 5 * 60

    from_timestamp = max(
        watermark - overlap_seconds,
        0,
    )


    filters = {
        "updatedAtFrom":
            from_timestamp,

        "updatedAtTo":
            to_timestamp,
    }


    logger.info(
        "CUSTOMER INCREMENTAL: %s -> %s",
        unix_to_datetime(
            from_timestamp
        ),
        unix_to_datetime(
            to_timestamp
        ),
    )


    pages, received = fetch_customers(
        filters=filters
    )


    # Chỉ update watermark sau khi
    # toàn bộ incremental thành công.
    save_watermark(
        to_timestamp
    )


    logger.info(
        "CUSTOMER INCREMENTAL COMPLETE | "
        "pages=%s | API customers=%s | "
        "new watermark=%s",
        pages,
        received,
        to_timestamp,
    )


# ============================================================
# 14. QUALITY CHECK
# ============================================================

def quality_check() -> None:

    sql = """
    SELECT

        COUNT(*) AS total_customers,

        COUNT(*) FILTER (
            WHERE customer_id IS NULL
        ) AS missing_customer_id,

        COUNT(*) FILTER (
            WHERE api_response IS NULL
        ) AS missing_payload,

        MIN(source_updated_at),

        MAX(source_updated_at)

    FROM raw.nhanh_customers;
    """


    conn = get_connection()

    try:

        with conn.cursor() as cur:

            cur.execute(sql)

            row = cur.fetchone()


        logger.info(
            "CUSTOMER RAW CHECK | "
            "customers=%s | "
            "missing_id=%s | "
            "missing_payload=%s | "
            "oldest_update=%s | "
            "latest_update=%s",
            *row,
        )


        if row[1] != 0:

            raise RuntimeError(
                "Customer RAW quality failed: "
                "missing customer_id."
            )


        if row[2] != 0:

            raise RuntimeError(
                "Customer RAW quality failed: "
                "missing api_response."
            )


    finally:
        conn.close()


# ============================================================
# 15. MAIN
# ============================================================

def main() -> None:

    logger.info("=" * 70)

    logger.info(
        "NHANH.VN CUSTOMER -> POSTGRES RAW"
    )

    logger.info("=" * 70)


    logger.info(
        "API: %s",
        API_URL,
    )

    logger.info(
        "appId=%s",
        APP_ID,
    )

    logger.info(
        "businessId=%s",
        BUSINESS_ID,
    )

    logger.info(
        "accessToken=%s",
        mask_token(
            ACCESS_TOKEN
        ),
    )


    initialize_database()


    watermark = get_watermark()


    if watermark is None:

        logger.info(
            "No customer watermark found "
            "-> INITIAL FULL LOAD"
        )

        run_initial_full_load()

    else:

        logger.info(
            "Customer watermark found: "
            "%s (%s)",
            watermark,
            unix_to_datetime(
                watermark
            ),
        )

        run_incremental(
            watermark
        )


    quality_check()


    logger.info("=" * 70)

    logger.info(
        "CUSTOMER PIPELINE SUCCESS"
    )

    logger.info("=" * 70)


if __name__ == "__main__":

    try:
        main()

    except KeyboardInterrupt:

        logger.warning(
            "Customer pipeline stopped by user."
        )

        sys.exit(130)

    except Exception as exc:

        logger.exception(
            "CUSTOMER PIPELINE FAILED: %s",
            exc,
        )

        sys.exit(1)