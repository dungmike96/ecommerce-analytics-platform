"""ZOSEO GA4 marketing analytics -> PostgreSQL RAW.

Usage:
 python ingestion/ingest_ga4_mkt.py --property 559523192 --stream 16155876969 --start 2026-10-20 --end 2026-10-26
 python ingestion/ingest_ga4_mkt.py --property 559523192 --stream 16155876969 --start 2026-10-20 --end 2026-10-26 --dry-run

Prerequisites: pip install google-analytics-data psycopg2-binary python-dotenv
Credentials (đọc từ .env ở thư mục gốc dự án, hoặc biến môi trường):
  GOOGLE_APPLICATION_CREDENTIALS
  DB_HOST / DB_PORT / DB_NAME / DB_USER / DB_PASSWORD   (cùng tên với script Nhanh)
  hoặc PGHOST / PGPORT / PGDATABASE / PGUSER / PGPASSWORD (tên cũ, vẫn được chấp nhận)
Create RAW tables using the DDL in the project before the first run.
"""
import argparse
import os
import time
from datetime import date
from decimal import Decimal
from pathlib import Path

from dotenv import load_dotenv
from google.api_core import exceptions as gexc

# Nạp .env từ thư mục gốc dự án (file này nằm trong ingestion\, nên parents[1] là gốc)
PROJECT_ROOT = Path(__file__).resolve().parents[1]
load_dotenv(PROJECT_ROOT / ".env")

from google.analytics.data_v1beta import BetaAnalyticsDataClient
from google.analytics.data_v1beta.types import (
    DateRange, Dimension, Filter, FilterExpression, Metric, RunReportRequest,
)
import psycopg2
from psycopg2.extras import execute_values

# Each report has one explicit grain. Keep independent: no JOIN of aggregated GA4 reports.
# Note: total_users is not additive across rows; do not SUM it across events or days.
REPORTS = {
    "traffic": {
        "table": "raw.ga4_traffic_acquisition_daily",
        "dimensions": ["date", "streamId", "sessionSource", "sessionMedium", "sessionCampaignName", "deviceCategory"],
        "metrics": ["sessions", "engagedSessions", "totalUsers", "ecommercePurchases", "engagementRate", "bounceRate"],
        "columns": ["property_id", "stream_id", "report_date", "session_source", "session_medium", "session_campaign_name", "device_category",
                    "sessions", "engaged_sessions", "total_users", "ecommerce_purchases", "engagement_rate", "bounce_rate"],
        "key": ["property_id", "stream_id", "report_date", "session_source", "session_medium", "session_campaign_name", "device_category"],
        "sum_col": "sessions",
    },
    "landing": {
        "table": "raw.ga4_landing_pages_daily",
        "dimensions": ["date", "streamId", "landingPage", "sessionSource", "sessionMedium", "sessionCampaignName"],
        "metrics": ["sessions", "engagedSessions", "ecommercePurchases", "engagementRate", "bounceRate"],
        "columns": ["property_id", "stream_id", "report_date", "landing_page", "session_source", "session_medium", "session_campaign_name",
                    "sessions", "engaged_sessions", "ecommerce_purchases", "engagement_rate", "bounce_rate"],
        "key": ["property_id", "stream_id", "report_date", "landing_page", "session_source", "session_medium", "session_campaign_name"],
        "sum_col": "sessions",
    },
    "events": {
        "table": "raw.ga4_events_daily",
        "dimensions": ["date", "streamId", "eventName", "sessionSource", "sessionMedium"],
        "metrics": ["eventCount", "totalUsers"],
        "columns": ["property_id", "stream_id", "report_date", "event_name",
                    "session_source", "session_medium", "event_count", "total_users"],
        "key": ["property_id", "stream_id", "report_date", "event_name", "session_source", "session_medium"],
        "sum_col": "event_count",
    },
}


# GA4 hay trả 504/503/429 tạm thời. Mặc định timeout ~60s là quá ngắn cho report nhiều dimension.
GA4_TIMEOUT_SEC = int(os.getenv("GA4_TIMEOUT_SEC", "240"))
GA4_MAX_RETRIES = int(os.getenv("GA4_MAX_RETRIES", "4"))
RETRYABLE = (gexc.DeadlineExceeded, gexc.ServiceUnavailable,
             gexc.InternalServerError, gexc.TooManyRequests)


def run_report_with_retry(client, req, kind):
    for attempt in range(1, GA4_MAX_RETRIES + 1):
        try:
            return client.run_report(req, timeout=GA4_TIMEOUT_SEC)
        except RETRYABLE as exc:
            if attempt == GA4_MAX_RETRIES:
                raise
            wait = 10 * 3 ** (attempt - 1)  # 10s, 30s, 90s
            print(f"[retry] {kind}: {type(exc).__name__} (lan {attempt}/{GA4_MAX_RETRIES}), cho {wait}s", flush=True)
            time.sleep(wait)


def get_db_args():
    """Đọc kết nối PostgreSQL: ưu tiên DB_* (giống script Nhanh), fallback PG*."""
    return dict(
        host=os.getenv("DB_HOST") or os.getenv("PGHOST", "localhost"),
        port=os.getenv("DB_PORT") or os.getenv("PGPORT", "5432"),
        dbname=os.getenv("DB_NAME") or os.getenv("PGDATABASE", "data_center"),
        user=os.getenv("DB_USER") or os.getenv("PGUSER"),
        password=os.getenv("DB_PASSWORD") or os.getenv("PGPASSWORD"),
    )


def to_date(ga_date):
    # GA4 returns dates as YYYYMMDD
    return date.fromisoformat(f"{ga_date[:4]}-{ga_date[4:6]}-{ga_date[6:]}")


def build_row(kind, property_id, d, m):
    """Map one GA4 row to a tuple matching REPORTS[kind]['columns']."""
    stream_id = d[1]
    report_date = to_date(d[0])
    if kind == "traffic":
        return (property_id, stream_id, report_date, *d[2:6],
                *map(int, m[0:4]), Decimal(m[4]), Decimal(m[5]))
    if kind == "landing":
        return (property_id, stream_id, report_date, *d[2:6],
                *map(int, m[0:3]), Decimal(m[3]), Decimal(m[4]))
    if kind == "events":
        return (property_id, stream_id, report_date, d[2], d[3], d[4],
                int(m[0]), int(m[1]))
    raise ValueError(f"Unknown report kind: {kind}")


def extract(client, property_id, stream_id, start, end, kind, cfg):
    offset = 0
    result = []
    while True:
        req = RunReportRequest(
            property=f"properties/{property_id}",
            date_ranges=[DateRange(start_date=start, end_date=end)],
            dimensions=[Dimension(name=n) for n in cfg["dimensions"]],
            metrics=[Metric(name=n) for n in cfg["metrics"]],
            dimension_filter=FilterExpression(filter=Filter(
                field_name="streamId", string_filter=Filter.StringFilter(value=stream_id))),
            limit=10000, offset=offset,
        )
        response = run_report_with_retry(client, req, kind)
        for row in response.rows:
            d = [v.value for v in row.dimension_values]
            m = [v.value for v in row.metric_values]
            if len(d) != len(cfg["dimensions"]) or len(m) != len(cfg["metrics"]):
                raise RuntimeError(f"{kind}: unexpected shape d={len(d)} m={len(m)}")
            if d[1] != stream_id:
                raise RuntimeError(f"Unexpected stream ID from API: {d[1]}")
            result.append(build_row(kind, property_id, d, m))
        offset += len(response.rows)
        if offset >= response.row_count or not response.rows:
            break
    return result


def upsert(conn, cfg, rows):
    if not rows:
        return
    columns = cfg["columns"]
    key = cfg["key"]
    mutable = [c for c in columns if c not in key]
    # Table and column names come only from REPORTS, never from user input.
    sql = (f"INSERT INTO {cfg['table']} ({', '.join(columns)}) VALUES %s "
           f"ON CONFLICT ({', '.join(key)}) DO UPDATE SET "
           + ", ".join(f"{c} = EXCLUDED.{c}" for c in mutable)
           + ", ingested_at = now()")
    with conn.cursor() as cur:
        execute_values(cur, sql, rows, page_size=500)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--property", required=True, help="GA4 numeric Property ID")
    p.add_argument("--stream", required=True, help="GA4 numeric Stream ID; verify in Admin")
    p.add_argument("--start", required=True, help="YYYY-MM-DD")
    p.add_argument("--end", required=True, help="YYYY-MM-DD")
    p.add_argument("--dry-run", action="store_true", help="Only query GA4, do not write PostgreSQL")
    args = p.parse_args()

    if date.fromisoformat(args.start) > date.fromisoformat(args.end):
        p.error("--start must be <= --end")
    if not args.property.isdigit() or not args.stream.isdigit():
        p.error("--property and --stream must be numeric")
    if not os.getenv("GOOGLE_APPLICATION_CREDENTIALS"):
        p.error("GOOGLE_APPLICATION_CREDENTIALS is missing (đặt trong .env)")

    # Kiểm tra kết nối DB trước khi gọi GA4, tránh tốn quota rồi mới lỗi
    db_args = get_db_args()
    if not args.dry_run and not db_args["user"]:
        p.error("DB_USER (hoặc PGUSER) chưa được đặt trong .env")

    client = BetaAnalyticsDataClient()
    all_rows = {}
    for kind, cfg in REPORTS.items():
        try:
            rows = extract(client, args.property, args.stream, args.start, args.end, kind, cfg)
        except Exception as exc:
            raise RuntimeError(
                f"GA4 {kind} report failed: {exc}. Check Property/Stream permissions and GA4 dimension-metric compatibility."
            ) from exc
        all_rows[kind] = rows
        idx = cfg["columns"].index(cfg["sum_col"])
        total = sum(r[idx] for r in rows)
        print(f"{kind}: {len(rows)} rows; {cfg['sum_col']} sum={total}")
        for r in rows[:3]:
            print("  SAMPLE", dict(zip(cfg["columns"], map(str, r))))

    if args.dry_run:
        print("DRY RUN complete: PostgreSQL unchanged")
        return

    # psycopg2 commits all loads together when the with-block exits cleanly.
    with psycopg2.connect(**db_args) as conn:
        for kind, cfg in REPORTS.items():
            upsert(conn, cfg, all_rows[kind])
            print(f"UPSERT {cfg['table']}: {len(all_rows[kind])} rows")
    print("OK: GA4 marketing RAW loaded. Source reports are aggregates, not user-level sessions.")


if __name__ == "__main__":
    main()