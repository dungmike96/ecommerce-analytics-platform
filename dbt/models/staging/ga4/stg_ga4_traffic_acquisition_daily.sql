{{ config(materialized='view') }}

select
    property_id,
    stream_id,
    report_date,
    coalesce(nullif(session_source, ''), '(not set)')         as session_source,
    coalesce(nullif(session_medium, ''), '(not set)')         as session_medium,
    coalesce(nullif(session_campaign_name, ''), '(not set)')  as session_campaign_name,
    coalesce(nullif(device_category, ''), '(not set)')        as device_category,
    sessions,
    engaged_sessions,
    total_users,
    ecommerce_purchases,
    ingested_at
from {{ source('raw', 'ga4_traffic_acquisition_daily') }}