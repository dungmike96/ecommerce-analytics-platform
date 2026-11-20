BEGIN;

CREATE SCHEMA IF NOT EXISTS raw;

ALTER TABLE raw.nhanh_orders
    ADD COLUMN IF NOT EXISTS source_app_id TEXT,
    ADD COLUMN IF NOT EXISTS source_business_id TEXT,
    ADD COLUMN IF NOT EXISTS source_depot_id BIGINT,
    ADD COLUMN IF NOT EXISTS source_created_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS source_updated_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS first_ingested_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS last_ingested_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_nhanh_orders_source_created
    ON raw.nhanh_orders(source_created_at);

CREATE INDEX IF NOT EXISTS idx_nhanh_orders_source_updated
    ON raw.nhanh_orders(source_updated_at);

CREATE INDEX IF NOT EXISTS idx_nhanh_orders_depot
    ON raw.nhanh_orders(source_depot_id);

COMMIT;