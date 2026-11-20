{{ config(materialized='view') }}

select
    property_id,
    stream_id,
    report_date,
    landing_page,
    coalesce(nullif(session_source, ''), '(not set)')         as session_source,
    coalesce(nullif(session_medium, ''), '(not set)')         as session_medium,
    coalesce(nullif(session_campaign_name, ''), '(not set)')  as session_campaign_name,
    sessions,
    engaged_sessions,
    ecommerce_purchases,
    ingested_at
from {{ source('raw', 'ga4_landing_pages_daily') }}