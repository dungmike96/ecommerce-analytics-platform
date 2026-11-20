{{ config(materialized='table', schema='analytics') }}

-- Grain: 1 dòng = property + stream + ngày + event + source + medium.
-- event_count cộng dồn được. total_users KHÔNG cộng dồn được qua ngày/event/source,
-- nên giữ nguyên theo grain này, không SUM.
select
    property_id,
    stream_id,
    report_date,
    event_name,
    session_source,
    session_medium,
    event_count,
    total_users
from {{ ref('stg_ga4_events_daily') }}