-- ZOSEO GA4 Marketing Analytics | raw layer | additive-safe grain
-- Run once against PostgreSQL data_center. Non-destructive.
CREATE SCHEMA IF NOT EXISTS raw;

CREATE TABLE IF NOT EXISTS raw.ga4_traffic_acquisition_daily (
    property_id text NOT NULL,
    stream_id text NOT NULL,
    report_date date NOT NULL,
    session_source text NOT NULL,
    session_medium text NOT NULL,
    session_campaign_name text NOT NULL,
    device_category text NOT NULL,
    sessions bigint NOT NULL DEFAULT 0,
    engaged_sessions bigint NOT NULL DEFAULT 0,
    total_users bigint NOT NULL DEFAULT 0,
    ecommerce_purchases bigint NOT NULL DEFAULT 0,
    engagement_rate numeric(12,8),
    bounce_rate numeric(12,8),
    ingested_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (property_id, stream_id, report_date, session_source, session_medium, session_campaign_name, device_category)
);

CREATE TABLE IF NOT EXISTS raw.ga4_landing_pages_daily (
    property_id text NOT NULL,
    stream_id text NOT NULL,
    report_date date NOT NULL,
    landing_page text NOT NULL,
    session_source text NOT NULL,
    session_medium text NOT NULL,
    session_campaign_name text NOT NULL,
    sessions bigint NOT NULL DEFAULT 0,
    engaged_sessions bigint NOT NULL DEFAULT 0,
    ecommerce_purchases bigint NOT NULL DEFAULT 0,
    engagement_rate numeric(12,8),
    bounce_rate numeric(12,8),
    ingested_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (property_id, stream_id, report_date, landing_page, session_source, session_medium, session_campaign_name)
);

CREATE INDEX IF NOT EXISTS ix_ga4_traffic_date ON raw.ga4_traffic_acquisition_daily (report_date);
CREATE INDEX IF NOT EXISTS ix_ga4_landing_date ON raw.ga4_landing_pages_daily (report_date);
