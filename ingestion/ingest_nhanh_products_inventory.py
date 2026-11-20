import os
import sys
import time
import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import psycopg2
import requests
from dotenv import load_dotenv
from psycopg2.extras import Json, execute_values
from zoneinfo import ZoneInfo


# ============================================================
# PROJECT / ENV
# ============================================================

PROJECT_ROOT = Path(__file__).resolve().parents[1]
load_dotenv(PROJECT_ROOT / ".env")

APP_ID = os.getenv("NHANH_APP_ID")
BUSINESS_ID = os.getenv("NHANH_BUSINESS_ID")
ACCESS_TOKEN = os.getenv("NHANH_ACCESS_TOKEN")

DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = int(os.getenv("DB_PORT", "5432"))
DB_NAME = os.getenv("DB_NAME", "data_center")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD")

PAGE_SIZE = min(
    int(os.getenv("NHANH_PRODUCT_PAGE_SIZE", "100")),
    100,
)

REQUEST_TIMEOUT = int(
    os.getenv("NHANH_REQUEST_TIMEOUT", "60")
)

MAX_RETRIES = int(
    os.getenv("NHANH_MAX_RETRIES", "5")
)

RETRY_BASE_SECONDS = float(
    os.getenv("NHANH_RETRY_BASE_SECONDS", "2")
)

VIETNAM_TZ = ZoneInfo("Asia/Ho_Chi_Minh")

API_URL = "https://pos.open.nhanh.vn/v3.0/product/list"


# ============================================================
# LOGGING
# ============================================================

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
)

logger = logging.getLogger(__name__)


# ============================================================
# VALIDATION
# ============================================================

def validate_config() -> None:

    required = {
        "NHANH_APP_ID": APP_ID,
        "NHANH_BUSINESS_ID": BUSINESS_ID,
        "NHANH_ACCESS_TOKEN": ACCESS_TOKEN,
        "DB_PASSWORD": DB_PASSWORD,
    }

    missing = [
        key
        for key, value in required.items()
        if not value
    ]

    if missing:
        raise RuntimeError(
            "Missing required environment variables: "
            + ", ".join(missing)
        )

    if PAGE_SIZE <= 0:
        raise RuntimeError(
            "NHANH_PRODUCT_PAGE_SIZE must be greater than 0"
        )


# ============================================================
# DATABASE
# ============================================================

def get_db_connection():

    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
    )


def ensure_raw_tables(conn) -> None:

    ddl = """
    CREATE SCHEMA IF NOT EXISTS raw;

    CREATE TABLE IF NOT EXISTS raw.nhanh_products (
        product_id BIGINT PRIMARY KEY,

        api_response JSONB NOT NULL,

        source_app_id TEXT NOT NULL,
        source_business_id TEXT NOT NULL,

        source_created_at TIMESTAMPTZ,
        source_updated_at TIMESTAMPTZ,

        first_ingested_at TIMESTAMPTZ NOT NULL
            DEFAULT CURRENT_TIMESTAMP,

        last_ingested_at TIMESTAMPTZ NOT NULL
            DEFAULT CURRENT_TIMESTAMP
    );

    CREATE INDEX IF NOT EXISTS
        idx_nhanh_products_source_updated_at
    ON raw.nhanh_products(source_updated_at);


    CREATE TABLE IF NOT EXISTS raw.nhanh_inventory_snapshots (
        snapshot_date DATE NOT NULL,

        product_id BIGINT NOT NULL,
        depot_id BIGINT NOT NULL,

        api_response JSONB NOT NULL,

        source_app_id TEXT NOT NULL,
        source_business_id TEXT NOT NULL,

        snapshot_at TIMESTAMPTZ NOT NULL,

        PRIMARY KEY (
            snapshot_date,
            product_id,
            depot_id
        )
    );

    CREATE INDEX IF NOT EXISTS
        idx_nhanh_inventory_snapshot_date
    ON raw.nhanh_inventory_snapshots(snapshot_date);

    CREATE INDEX IF NOT EXISTS
        idx_nhanh_inventory_product_id
    ON raw.nhanh_inventory_snapshots(product_id);

    CREATE INDEX IF NOT EXISTS
        idx_nhanh_inventory_depot_id
    ON raw.nhanh_inventory_snapshots(depot_id);
    """

    with conn.cursor() as cur:
        cur.execute(ddl)

    conn.commit()


# ============================================================
# TIMESTAMP HELPERS
# ============================================================

def unix_to_datetime(value: Any):

    if value in (None, "", 0, "0"):
        return None

    try:
        timestamp_value = int(value)

        return datetime.fromtimestamp(
            timestamp_value,
            tz=timezone.utc,
        )

    except (TypeError, ValueError, OverflowError):
        return None


# ============================================================
# HTTP SESSION
# ============================================================

def build_session() -> requests.Session:

    session = requests.Session()

    session.headers.update(
        {
            "Authorization": ACCESS_TOKEN,
            "Content-Type": "application/json",
        }
    )

    return session


def post_with_retry(
    session: requests.Session,
    payload: dict,
) -> dict:

    params = {
        "appId": APP_ID,
        "businessId": BUSINESS_ID,
    }

    last_error = None

    for attempt in range(1, MAX_RETRIES + 1):

        try:

            response = session.post(
                API_URL,
                params=params,
                json=payload,
                timeout=REQUEST_TIMEOUT,
            )

            # Rate limit / temporary server errors
            if response.status_code == 429 or 500 <= response.status_code < 600:

                wait_seconds = (
                    RETRY_BASE_SECONDS
                    * (2 ** (attempt - 1))
                )

                logger.warning(
                    "Temporary API error HTTP %s | "
                    "attempt=%s/%s | retry_in=%.1fs",
                    response.status_code,
                    attempt,
                    MAX_RETRIES,
                    wait_seconds,
                )

                time.sleep(wait_seconds)
                continue

            response.raise_for_status()

            result = response.json()

            if result.get("code") != 1:
                raise RuntimeError(
                    "Nhanh API returned unsuccessful response: "
                    f"{result}"
                )

            return result

        except (
            requests.RequestException,
            ValueError,
            RuntimeError,
        ) as exc:

            last_error = exc

            if attempt >= MAX_RETRIES:
                break

            wait_seconds = (
                RETRY_BASE_SECONDS
                * (2 ** (attempt - 1))
            )

            logger.warning(
                "API request failed | "
                "attempt=%s/%s | error=%s | retry_in=%.1fs",
                attempt,
                MAX_RETRIES,
                exc,
                wait_seconds,
            )

            time.sleep(wait_seconds)

    raise RuntimeError(
        f"Nhanh Product API failed after {MAX_RETRIES} attempts: "
        f"{last_error}"
    )


# ============================================================
# API PAGINATION
# ============================================================

def fetch_all_products(
    session: requests.Session,
) -> list[dict]:

    all_products = []

    next_cursor = None
    page_number = 0

    seen_product_ids = set()

    while True:

        paginator = {
            "size": PAGE_SIZE,
            "sort": {
                "id": "desc",
            },
        }

        if next_cursor is not None:
            paginator["next"] = next_cursor

        payload = {
            "filters": {},
            "paginator": paginator,
        }

        result = post_with_retry(
            session=session,
            payload=payload,
        )

        data = result.get("data") or []

        page_number += 1

        logger.info(
            "PRODUCT API | page=%s | rows=%s",
            page_number,
            len(data),
        )

        for product in data:

            product_id = product.get("id")

            if product_id is None:
                raise RuntimeError(
                    "Product API returned a record without product.id"
                )

            product_id = int(product_id)

            if product_id in seen_product_ids:
                raise RuntimeError(
                    "Duplicate product_id returned during full scan: "
                    f"{product_id}"
                )

            seen_product_ids.add(product_id)
            all_products.append(product)

        paginator_response = result.get("paginator") or {}
        next_cursor = paginator_response.get("next")

        if not next_cursor:
            break

        if not data:
            raise RuntimeError(
                "Nhanh API returned paginator.next "
                "but current page has no data"
            )

    logger.info(
        "PRODUCT API COMPLETE | pages=%s | products=%s",
        page_number,
        len(all_products),
    )

    return all_products


# ============================================================
# PRODUCT UPSERT
# ============================================================

def upsert_products(
    conn,
    products: list[dict],
) -> int:

    if not products:
        return 0

    rows = []

    for product in products:

        product_id = int(product["id"])

        source_created_at = unix_to_datetime(
            product.get("createdAt")
        )

        source_updated_at = unix_to_datetime(
            product.get("updatedAt")
        )

        rows.append(
            (
                product_id,
                Json(product),
                str(APP_ID),
                str(BUSINESS_ID),
                source_created_at,
                source_updated_at,
            )
        )

    sql = """
    INSERT INTO raw.nhanh_products (
        product_id,
        api_response,
        source_app_id,
        source_business_id,
        source_created_at,
        source_updated_at,
        first_ingested_at,
        last_ingested_at
    )
    VALUES %s

    ON CONFLICT (product_id)
    DO UPDATE SET

        api_response =
            EXCLUDED.api_response,

        source_app_id =
            EXCLUDED.source_app_id,

        source_business_id =
            EXCLUDED.source_business_id,

        source_created_at =
            EXCLUDED.source_created_at,

        source_updated_at =
            EXCLUDED.source_updated_at,

        last_ingested_at =
            CURRENT_TIMESTAMP
    ;
    """

    template = """
    (
        %s,
        %s,
        %s,
        %s,
        %s,
        %s,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
    )
    """

    with conn.cursor() as cur:

        execute_values(
            cur,
            sql,
            rows,
            template=template,
            page_size=500,
        )

    return len(rows)


# ============================================================
# INVENTORY EXTRACTION
# ============================================================

def build_inventory_rows(
    products: list[dict],
    snapshot_date,
    snapshot_at,
) -> tuple[list[tuple], dict]:

    rows = []

    seen_keys = set()

    stats = {
        "products": len(products),
        "products_with_inventory": 0,
        "products_with_depots": 0,
        "products_without_depots": 0,
        "inventory_rows": 0,
        "negative_remain_rows": 0,
        "depot_ids": set(),
    }

    for product in products:

        product_id = int(product["id"])

        inventory = product.get("inventory")

        if not isinstance(inventory, dict):
            continue

        stats["products_with_inventory"] += 1

        depots = inventory.get("depots") or []

        if depots:
            stats["products_with_depots"] += 1
        else:
            stats["products_without_depots"] += 1

        for depot in depots:

            depot_id = depot.get("id")

            if depot_id is None:
                raise RuntimeError(
                    "Inventory depot record missing depot.id | "
                    f"product_id={product_id}"
                )

            depot_id = int(depot_id)

            key = (
                snapshot_date,
                product_id,
                depot_id,
            )

            if key in seen_keys:
                raise RuntimeError(
                    "Duplicate inventory snapshot key: "
                    f"{key}"
                )

            seen_keys.add(key)

            stats["depot_ids"].add(depot_id)

            remain = depot.get("remain")

            try:
                if (
                    remain is not None
                    and float(remain) < 0
                ):
                    stats["negative_remain_rows"] += 1
            except (TypeError, ValueError):
                pass

            # Keep the depot-level inventory exactly as returned,
            # but include minimal product context for RAW auditing.
            inventory_payload = {
                "product": {
                    "id": product.get("id"),
                    "parentId": product.get("parentId"),
                    "code": product.get("code"),
                    "barcode": product.get("barcode"),
                    "name": product.get("name"),
                    "status": product.get("status"),
                },
                "inventory": {
                    "productTotal": {
                        "remain": inventory.get("remain"),
                        "shipping": inventory.get("shipping"),
                        "damaged": inventory.get("damaged"),
                        "holding": inventory.get("holding"),
                        "transfering": inventory.get("transfering"),
                        "available": inventory.get("available"),
                        "warranty": inventory.get("warranty"),
                    },
                    "depot": depot,
                },
            }

            rows.append(
                (
                    snapshot_date,
                    product_id,
                    depot_id,
                    Json(inventory_payload),
                    str(APP_ID),
                    str(BUSINESS_ID),
                    snapshot_at,
                )
            )

    stats["inventory_rows"] = len(rows)

    return rows, stats


# ============================================================
# INVENTORY UPSERT
# ============================================================

def upsert_inventory_snapshot(
    conn,
    rows: list[tuple],
) -> int:

    if not rows:
        return 0

    sql = """
    INSERT INTO raw.nhanh_inventory_snapshots (
        snapshot_date,
        product_id,
        depot_id,
        api_response,
        source_app_id,
        source_business_id,
        snapshot_at
    )
    VALUES %s

    ON CONFLICT (
        snapshot_date,
        product_id,
        depot_id
    )
    DO UPDATE SET

        api_response =
            EXCLUDED.api_response,

        source_app_id =
            EXCLUDED.source_app_id,

        source_business_id =
            EXCLUDED.source_business_id,

        snapshot_at =
            EXCLUDED.snapshot_at
    ;
    """

    with conn.cursor() as cur:

        execute_values(
            cur,
            sql,
            rows,
            page_size=500,
        )

    return len(rows)


# ============================================================
# SAME-DAY SNAPSHOT CLEANUP
# ============================================================

def remove_stale_same_day_inventory_rows(
    conn,
    snapshot_date,
    current_keys: set[tuple[int, int]],
) -> int:
    """
    A rerun on the same date must represent the current full API scan.

    Example:
      09:00 product A has depot row -> inserted.
      15:00 API no longer returns that product/depot row.

    Without cleanup, the 09:00 row would incorrectly remain in the
    snapshot table. Since this ingestion performs a FULL scan, rows
    absent from the current scan must be removed for today's snapshot.
    """

    with conn.cursor() as cur:

        cur.execute(
            """
            SELECT
                product_id,
                depot_id
            FROM raw.nhanh_inventory_snapshots
            WHERE snapshot_date = %s
            """,
            (snapshot_date,),
        )

        existing_keys = {
            (int(product_id), int(depot_id))
            for product_id, depot_id in cur.fetchall()
        }

        stale_keys = existing_keys - current_keys

        if not stale_keys:
            return 0

        cur.executemany(
            """
            DELETE FROM raw.nhanh_inventory_snapshots
            WHERE snapshot_date = %s
              AND product_id = %s
              AND depot_id = %s
            """,
            [
                (
                    snapshot_date,
                    product_id,
                    depot_id,
                )
                for product_id, depot_id in stale_keys
            ],
        )

    return len(stale_keys)


# ============================================================
# QUALITY CHECKS
# ============================================================

def run_quality_checks(
    conn,
    snapshot_date,
    expected_product_ids: set[int],
    expected_inventory_keys: set[tuple[int, int]],
) -> None:

    with conn.cursor() as cur:

        # ----------------------------------------------------
        # PRODUCT MASTER
        # ----------------------------------------------------

        cur.execute(
            """
            SELECT
                COUNT(*) AS total_rows,
                COUNT(DISTINCT product_id) AS distinct_products,
                COUNT(*) FILTER (
                    WHERE product_id IS NULL
                ) AS missing_product_id,
                COUNT(*) FILTER (
                    WHERE api_response IS NULL
                ) AS missing_payload
            FROM raw.nhanh_products
            """
        )

        (
            total_products,
            distinct_products,
            missing_product_id,
            missing_product_payload,
        ) = cur.fetchone()

        # ----------------------------------------------------
        # CURRENT SNAPSHOT
        # ----------------------------------------------------

        cur.execute(
            """
            SELECT
                COUNT(*) AS total_rows,

                COUNT(
                    DISTINCT (product_id, depot_id)
                ) AS distinct_product_depot,

                COUNT(DISTINCT product_id)
                    AS distinct_products,

                COUNT(DISTINCT depot_id)
                    AS distinct_depots,

                COUNT(*) FILTER (
                    WHERE product_id IS NULL
                       OR depot_id IS NULL
                ) AS missing_key,

                COUNT(*) FILTER (
                    WHERE api_response IS NULL
                ) AS missing_payload

            FROM raw.nhanh_inventory_snapshots

            WHERE snapshot_date = %s
            """,
            (snapshot_date,),
        )

        (
            inventory_rows,
            distinct_inventory_keys,
            inventory_products,
            distinct_depots,
            missing_inventory_key,
            missing_inventory_payload,
        ) = cur.fetchone()

        # ----------------------------------------------------
        # CHECK CURRENT PRODUCT IDS EXIST IN RAW
        # ----------------------------------------------------

        cur.execute(
            """
            SELECT product_id
            FROM raw.nhanh_products
            """
        )

        raw_product_ids = {
            int(row[0])
            for row in cur.fetchall()
        }

    missing_products = (
        expected_product_ids
        - raw_product_ids
    )

    if missing_product_id != 0:
        raise RuntimeError(
            "Product quality check failed: "
            f"missing_product_id={missing_product_id}"
        )

    if missing_product_payload != 0:
        raise RuntimeError(
            "Product quality check failed: "
            f"missing_payload={missing_product_payload}"
        )

    if missing_products:
        raise RuntimeError(
            "Product quality check failed: "
            "API products missing from raw.nhanh_products: "
            f"{sorted(missing_products)[:20]}"
        )

    if missing_inventory_key != 0:
        raise RuntimeError(
            "Inventory quality check failed: "
            f"missing_key={missing_inventory_key}"
        )

    if missing_inventory_payload != 0:
        raise RuntimeError(
            "Inventory quality check failed: "
            f"missing_payload={missing_inventory_payload}"
        )

    if inventory_rows != len(expected_inventory_keys):
        raise RuntimeError(
            "Inventory quality check failed: "
            f"database_rows={inventory_rows}, "
            f"api_rows={len(expected_inventory_keys)}"
        )

    if distinct_inventory_keys != inventory_rows:
        raise RuntimeError(
            "Inventory quality check failed: "
            "duplicate product/depot snapshot keys detected"
        )

    logger.info(
        "PRODUCT RAW CHECK | "
        "rows=%s | distinct_products=%s | "
        "missing_id=%s | missing_payload=%s",
        total_products,
        distinct_products,
        missing_product_id,
        missing_product_payload,
    )

    logger.info(
        "INVENTORY RAW CHECK | "
        "snapshot_date=%s | rows=%s | "
        "products=%s | depots=%s | "
        "missing_key=%s | missing_payload=%s",
        snapshot_date,
        inventory_rows,
        inventory_products,
        distinct_depots,
        missing_inventory_key,
        missing_inventory_payload,
    )


# ============================================================
# MAIN
# ============================================================

def main() -> int:

    conn = None

    try:

        validate_config()

        # ----------------------------------------------------
        # Freeze snapshot time BEFORE API scan.
        # Every page belongs to the same logical snapshot.
        # ----------------------------------------------------

        snapshot_at = datetime.now(VIETNAM_TZ)
        snapshot_date = snapshot_at.date()

        logger.info(
            "============================================================"
        )
        logger.info(
            "NHANH PRODUCT + INVENTORY PIPELINE START"
        )
        logger.info(
            "snapshot_date=%s | snapshot_at=%s",
            snapshot_date,
            snapshot_at.isoformat(),
        )
        logger.info(
            "============================================================"
        )

        # ----------------------------------------------------
        # DATABASE
        # ----------------------------------------------------

        conn = get_db_connection()

        ensure_raw_tables(conn)

        # ----------------------------------------------------
        # FULL API SCAN
        # ----------------------------------------------------

        session = build_session()

        products = fetch_all_products(session)

        if not products:
            raise RuntimeError(
                "Product API full scan returned 0 products. "
                "Aborting to avoid treating an abnormal empty "
                "response as a valid inventory snapshot."
            )

        # ----------------------------------------------------
        # BUILD INVENTORY SNAPSHOT
        # ----------------------------------------------------

        inventory_rows, inventory_stats = (
            build_inventory_rows(
                products=products,
                snapshot_date=snapshot_date,
                snapshot_at=snapshot_at,
            )
        )

        if not inventory_rows:
            raise RuntimeError(
                "Product API returned products but 0 depot-level "
                "inventory rows. Aborting because this differs "
                "from the validated source behavior."
            )

        expected_product_ids = {
            int(product["id"])
            for product in products
        }

        expected_inventory_keys = {
            (
                int(row[1]),  # product_id
                int(row[2]),  # depot_id
            )
            for row in inventory_rows
        }

        logger.info(
            "API PROFILE | "
            "products=%s | "
            "products_with_inventory=%s | "
            "products_with_depots=%s | "
            "products_without_depots=%s | "
            "inventory_rows=%s | "
            "depots=%s | "
            "negative_remain_rows=%s",
            inventory_stats["products"],
            inventory_stats["products_with_inventory"],
            inventory_stats["products_with_depots"],
            inventory_stats["products_without_depots"],
            inventory_stats["inventory_rows"],
            sorted(inventory_stats["depot_ids"]),
            inventory_stats["negative_remain_rows"],
        )

        # ----------------------------------------------------
        # TRANSACTION:
        # Product + inventory must succeed together.
        # ----------------------------------------------------

        products_written = upsert_products(
            conn,
            products,
        )

        inventory_written = upsert_inventory_snapshot(
            conn,
            inventory_rows,
        )

        stale_rows_removed = (
            remove_stale_same_day_inventory_rows(
                conn=conn,
                snapshot_date=snapshot_date,
                current_keys=expected_inventory_keys,
            )
        )

        conn.commit()

        logger.info(
            "WRITE COMPLETE | "
            "products_upserted=%s | "
            "inventory_upserted=%s | "
            "stale_same_day_rows_removed=%s",
            products_written,
            inventory_written,
            stale_rows_removed,
        )

        # ----------------------------------------------------
        # QUALITY CHECK
        # ----------------------------------------------------

        run_quality_checks(
            conn=conn,
            snapshot_date=snapshot_date,
            expected_product_ids=expected_product_ids,
            expected_inventory_keys=expected_inventory_keys,
        )

        logger.info(
            "============================================================"
        )
        logger.info(
            "NHANH PRODUCT + INVENTORY PIPELINE SUCCESS"
        )
        logger.info(
            "============================================================"
        )

        return 0

    except Exception as exc:

        if conn is not None:
            try:
                conn.rollback()
            except Exception:
                pass

        logger.exception(
            "NHANH PRODUCT + INVENTORY PIPELINE FAILED | %s",
            exc,
        )

        return 1

    finally:

        if conn is not None:
            conn.close()


if __name__ == "__main__":
    sys.exit(main())