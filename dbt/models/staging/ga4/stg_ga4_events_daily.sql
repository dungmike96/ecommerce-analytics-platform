{{ config(materialized='view') }}

select
    property_id,
    stream_id,
    report_date,
    event_name,
    coalesce(nullif(session_source, ''), '(not set)')  as session_source,
    coalesce(nullif(session_medium, ''), '(not set)')  as session_medium,
    event_count,
    total_users,
    ingested_at
from {{ source('raw', 'ga4_events_daily') }}