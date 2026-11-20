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

# ingest_nhanh_orders.py nằm trong:
# ecommerce-dwh/ingestion/
#
# .env nằm tại:
# ecommerce-dwh/.env

PROJECT_ROOT = Path(__file__).resolve().parent.parent
ENV_FILE = PROJECT_ROOT / ".env"

if not ENV_FILE.exists():
    raise RuntimeError(
        f"Không tìm thấy file .env tại: {ENV_FILE}"
    )

load_dotenv(dotenv_path=ENV_FILE)


def required_env(name: str) -> str:
    value = os.getenv(name, "").strip()

    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
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
        raise RuntimeError(f"{name} phải là số nguyên") from exc


# ============================================================
# 2. CONFIG
# ============================================================

APP_ID = required_env("NHANH_APP_ID")
BUSINESS_ID = required_env("NHANH_BUSINESS_ID")
ACCESS_TOKEN = required_env("NHANH_ACCESS_TOKEN")

if ACCESS_TOKEN.lower().startswith("bearer "):
    ACCESS_TOKEN = ACCESS_TOKEN[7:].strip()


# Ngày công ty bắt đầu có dữ liệu cần đưa vào DWH.
# Ví dụ: 2023-01-01
BACKFILL_START_DATE = required_env("NHANH_BACKFILL_START_DATE")


DB_CONFIG = {
    "host": required_env("DB_HOST"),
    "port": optional_int("DB_PORT", 5432),
    "database": required_env("DB_NAME"),
    "user": required_env("DB_USER"),
    "password": required_env("DB_PASSWORD"),
}


API_URL = "https://pos.open.nhanh.vn/v3.0/order/list"

PAGE_SIZE = min(optional_int("NHANH_PAGE_SIZE", 100), 100)
HTTP_TIMEOUT = optional_int("NHANH_HTTP_TIMEOUT", 60)
MAX_RETRIES = optional_int("NHANH_MAX_RETRIES", 3)


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

logger = logging.getLogger("nhanh_ingestion")


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

    CREATE TABLE IF NOT EXISTS raw.nhanh_orders (
        order_id TEXT PRIMARY KEY,

        api_response JSONB NOT NULL,

        source_app_id TEXT NOT NULL,
        source_business_id TEXT NOT NULL,

        source_depot_id BIGINT,

        source_created_at TIMESTAMPTZ,
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
        idx_nhanh_orders_source_created
    ON raw.nhanh_orders(source_created_at);


    CREATE INDEX IF NOT EXISTS
        idx_nhanh_orders_source_updated
    ON raw.nhanh_orders(source_updated_at);


    CREATE INDEX IF NOT EXISTS
        idx_nhanh_orders_depot
    ON raw.nhanh_orders(source_depot_id);
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

    logger.info("RAW database objects ready.")


# ============================================================
# 5. UNIX TIMESTAMP HELPERS
# ============================================================

def datetime_to_unix(dt: datetime) -> int:
    return int(dt.timestamp())


def unix_to_datetime(value: Optional[int]) -> Optional[datetime]:

    if not value:
        return None

    try:
        value = int(value)

        if value <= 0:
            return None

        return datetime.fromtimestamp(value, tz=VN_TZ)

    except (ValueError, TypeError, OSError):
        return None


# ============================================================
# 6. WATERMARK
# ============================================================

WATERMARK_NAME = "nhanh_orders_updated_at"


def get_watermark() -> Optional[int]:

    sql = """
        SELECT last_updated_at
        FROM raw.ingestion_watermark
        WHERE source_name = %s;
    """

    conn = get_connection()

    try:
        with conn.cursor() as cur:
            cur.execute(sql, (WATERMARK_NAME,))
            row = cur.fetchone()

        if row and row[0]:
            return int(row[0])

        return None

    finally:
        conn.close()


def save_watermark(timestamp_value: int) -> None:

    sql = """
        INSERT INTO raw.ingestion_watermark (
            source_name,
            last_updated_at,
            updated_at
        )
        VALUES (%s, %s, CURRENT_TIMESTAMP)

        ON CONFLICT (source_name)
        DO UPDATE SET
            last_updated_at = EXCLUDED.last_updated_at,
            updated_at = CURRENT_TIMESTAMP;
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


def call_nhanh_api(body: Dict[str, Any]) -> Dict[str, Any]:

    params = {
        "appId": APP_ID,
        "businessId": BUSINESS_ID,
    }

    for attempt in range(1, MAX_RETRIES + 1):

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
                f"Nha​​nh.vn trả response không phải JSON. "
                f"HTTP={response.status_code}, "
                f"response={response.text[:500]}"
            ) from exc


        if payload.get("code") == 1:
            return payload


        error_code = payload.get("errorCode")


        # Rate limit
        if error_code in {
            "ERR_429",
            "ERR_EXCEEDED_RATE_LIMIT",
        } and attempt < MAX_RETRIES:

            data = payload.get("data") or {}

            try:
                wait = max(
                    int(data.get("lockedSeconds", 1)),
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
            "Nhanh API error: "
            + json.dumps(
                payload,
                ensure_ascii=False,
                default=str,
            )
        )


    raise RuntimeError("Nhanh API failed after retries.")


# ============================================================
# 8. RESPONSE PARSER
# ============================================================

def parse_response(
    payload: Dict[str, Any]
) -> Tuple[List[Dict[str, Any]], Optional[Any]]:

    data = payload.get("data") or []

    if not isinstance(data, list):
        raise RuntimeError(
            "Response data của Nhanh không phải list như document."
        )

    orders = [
        item for item in data
        if isinstance(item, dict)
    ]

    paginator = payload.get("paginator") or {}

    next_cursor = (
        paginator.get("next")
        if isinstance(paginator, dict)
        else None
    )

    if next_cursor in ("", None, [], {}):
        next_cursor = None

    return orders, next_cursor


# ============================================================
# 9. ORDER FIELD HELPERS
# ============================================================

def get_info(order: Dict[str, Any]) -> Dict[str, Any]:

    info = order.get("info")

    return info if isinstance(info, dict) else {}


def get_order_id(order: Dict[str, Any]) -> Optional[str]:

    value = get_info(order).get("id")

    if value in (None, ""):
        return None

    return str(value)


# ============================================================
# 10. UPSERT
# ============================================================

def upsert_orders(orders: List[Dict[str, Any]]) -> int:

    if not orders:
        return 0


    sql = """
    INSERT INTO raw.nhanh_orders (
        order_id,
        api_response,

        source_app_id,
        source_business_id,
        source_depot_id,

        source_created_at,
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
        %s,
        %s,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
    )

    ON CONFLICT (order_id)

    DO UPDATE SET

        api_response =
            EXCLUDED.api_response,

        source_app_id =
            EXCLUDED.source_app_id,

        source_business_id =
            EXCLUDED.source_business_id,

        source_depot_id =
            EXCLUDED.source_depot_id,

        source_created_at =
            EXCLUDED.source_created_at,

        source_updated_at =
            EXCLUDED.source_updated_at,

        last_ingested_at =
            CURRENT_TIMESTAMP;
    """


    rows = []

    for order in orders:

        info = get_info(order)

        order_id = get_order_id(order)

        if not order_id:

            logger.warning(
                "Skip order without info.id"
            )
            continue


        depot_id = info.get("depotId")

        created_at = unix_to_datetime(
            info.get("createdAt")
        )

        updated_at = unix_to_datetime(
            info.get("updatedAt")
        )


        rows.append(
            (
                order_id,
                Json(order),
                APP_ID,
                BUSINESS_ID,
                depot_id,
                created_at,
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
# 11. FETCH ONE TIME WINDOW
# ============================================================

def fetch_window(
    filter_from_name: str,
    filter_to_name: str,
    from_timestamp: int,
    to_timestamp: int,
) -> Tuple[int, int]:

    next_cursor = None
    seen_cursors = set()

    pages = 0
    orders_received = 0


    while True:

        pages += 1

        filters = {
            filter_from_name: from_timestamp,
            filter_to_name: to_timestamp,
        }


        paginator = {
            "size": PAGE_SIZE,
        }


        if next_cursor is not None:
            paginator["next"] = next_cursor


        body = {
            "filters": filters,
            "paginator": paginator,
            "dataOptions": {},
        }


        logger.info(
            "%s=%s | %s=%s | page=%s",
            filter_from_name,
            from_timestamp,
            filter_to_name,
            to_timestamp,
            pages,
        )


        payload = call_nhanh_api(body)

        orders, returned_next = parse_response(payload)


        logger.info(
            "Page %s received %s orders",
            pages,
            len(orders),
        )


        if orders:

            upserted = upsert_orders(orders)

            orders_received += len(orders)

            logger.info(
                "Upserted %s orders.",
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
                "Paginator cursor lặp. "
                "Dừng để tránh infinite loop."
            )


        seen_cursors.add(cursor_key)
        next_cursor = returned_next


    return pages, orders_received


# ============================================================
# 12. INITIAL HISTORICAL BACKFILL
# ============================================================

def run_initial_backfill() -> None:

    logger.info("INITIAL BACKFILL START")


    try:
        start_date = datetime.strptime(
            BACKFILL_START_DATE,
            "%Y-%m-%d",
        ).replace(tzinfo=VN_TZ)

    except ValueError as exc:
        raise RuntimeError(
            "NHANH_BACKFILL_START_DATE phải có "
            "format YYYY-MM-DD"
        ) from exc


    now = datetime.now(VN_TZ)


    if start_date >= now:
        raise RuntimeError(
            "BACKFILL_START_DATE phải nhỏ hơn hiện tại."
        )


    window_start = start_date

    total_orders = 0
    total_pages = 0
    window_no = 0


    # Dùng 30 ngày để luôn nằm an toàn trong giới hạn <=31 ngày.
    while window_start < now:

        window_no += 1

        window_end = min(
            window_start + timedelta(days=30),
            now,
        )


        from_ts = datetime_to_unix(window_start)

        # -1 giây để cửa sổ không overlap với cửa sổ sau.
        to_ts = datetime_to_unix(window_end) - 1


        logger.info(
            "BACKFILL WINDOW %s: %s -> %s",
            window_no,
            window_start.isoformat(),
            datetime.fromtimestamp(
                to_ts,
                tz=VN_TZ,
            ).isoformat(),
        )


        pages, received = fetch_window(
            "createdAtFrom",
            "createdAtTo",
            from_ts,
            to_ts,
        )


        total_pages += pages
        total_orders += received


        logger.info(
            "WINDOW %s DONE | pages=%s | orders=%s",
            window_no,
            pages,
            received,
        )


        window_start = window_end


    # Sau khi backfill thành công toàn bộ,
    # watermark bắt đầu từ thời điểm kết thúc backfill.

    final_watermark = datetime_to_unix(now)

    save_watermark(final_watermark)


    logger.info(
        "INITIAL BACKFILL COMPLETE | "
        "windows=%s | pages=%s | API orders=%s",
        window_no,
        total_pages,
        total_orders,
    )


# ============================================================
# 13. INCREMENTAL UPDATED ORDERS
# ============================================================

def run_incremental(watermark: int) -> None:

    now = datetime.now(VN_TZ)

    to_timestamp = datetime_to_unix(now)


    # overlap 5 phút để tránh mất order ở biên thời gian
    overlap_seconds = 5 * 60

    from_timestamp = max(
        watermark - overlap_seconds,
        0,
    )


    # API giới hạn khoảng thời gian 31 ngày.
    # Bình thường job chạy 8h nên chỉ có một window.
    # Nhưng nếu scheduler chết nhiều ngày, vẫn chia window an toàn.

    current_start = datetime.fromtimestamp(
        from_timestamp,
        tz=VN_TZ,
    )

    final_end = datetime.fromtimestamp(
        to_timestamp,
        tz=VN_TZ,
    )


    total_orders = 0
    total_pages = 0


    while current_start < final_end:

        current_end = min(
            current_start + timedelta(days=30),
            final_end,
        )


        start_ts = datetime_to_unix(current_start)
        end_ts = datetime_to_unix(current_end)


        logger.info(
            "INCREMENTAL: %s -> %s",
            current_start.isoformat(),
            current_end.isoformat(),
        )


        pages, received = fetch_window(
            "updatedAtFrom",
            "updatedAtTo",
            start_ts,
            end_ts,
        )


        total_pages += pages
        total_orders += received


        current_start = current_end


    # Chỉ update watermark sau khi toàn bộ run thành công.
    save_watermark(to_timestamp)


    logger.info(
        "INCREMENTAL COMPLETE | "
        "pages=%s | API orders=%s | "
        "new watermark=%s",
        total_pages,
        total_orders,
        to_timestamp,
    )


# ============================================================
# 14. QUALITY CHECK
# ============================================================

def quality_check() -> None:

    sql = """
    SELECT
        COUNT(*) AS total_orders,

        COUNT(*) FILTER (
            WHERE order_id IS NULL
        ) AS missing_order_id,

        COUNT(*) FILTER (
            WHERE api_response IS NULL
        ) AS missing_payload,

        MIN(source_created_at),

        MAX(source_created_at),

        MAX(source_updated_at),

        COUNT(DISTINCT source_depot_id)

    FROM raw.nhanh_orders;
    """


    conn = get_connection()

    try:

        with conn.cursor() as cur:

            cur.execute(sql)

            row = cur.fetchone()


        logger.info(
            "RAW CHECK | "
            "orders=%s | "
            "missing_id=%s | "
            "missing_payload=%s | "
            "oldest=%s | "
            "newest=%s | "
            "latest_update=%s | "
            "depots=%s",
            *row,
        )


        if row[1] != 0:
            raise RuntimeError(
                "RAW quality failed: missing order_id."
            )

        if row[2] != 0:
            raise RuntimeError(
                "RAW quality failed: missing api_response."
            )


    finally:
        conn.close()


# ============================================================
# 15. MAIN
# ============================================================

def main() -> None:

    logger.info("=" * 70)
    logger.info("NHANH.VN -> POSTGRES RAW")
    logger.info("=" * 70)

    logger.info("API: %s", API_URL)
    logger.info("appId=%s", APP_ID)
    logger.info("businessId=%s", BUSINESS_ID)
    logger.info(
        "accessToken=%s",
        mask_token(ACCESS_TOKEN),
    )

    initialize_database()


    watermark = get_watermark()


    if watermark is None:

        logger.info(
            "No watermark found -> INITIAL BACKFILL"
        )

        run_initial_backfill()

    else:

        logger.info(
            "Watermark found: %s (%s)",
            watermark,
            unix_to_datetime(watermark),
        )

        run_incremental(watermark)


    quality_check()

    logger.info("=" * 70)
    logger.info("PIPELINE SUCCESS")
    logger.info("=" * 70)


if __name__ == "__main__":

    try:
        main()

    except KeyboardInterrupt:

        logger.warning("Pipeline stopped by user.")
        sys.exit(130)

    except Exception as exc:

        logger.exception(
            "PIPELINE FAILED: %s",
            exc,
        )

        sys.exit(1)