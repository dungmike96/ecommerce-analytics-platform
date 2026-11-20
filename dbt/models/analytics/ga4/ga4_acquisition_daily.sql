{{ config(materialized='table', schema='analytics') }}

select
    report_date,
    session_source,
    session_medium,
    session_campaign_name,
    sum(sessions)             as sessions,
    sum(engaged_sessions)     as engaged_sessions,
    sum(ecommerce_purchases)  as ecommerce_purchases,
    round(sum(engaged_sessions)::numeric / nullif(sum(sessions), 0), 4)       as engagement_rate,
    round(1 - sum(engaged_sessions)::numeric / nullif(sum(sessions), 0), 4)  as bounce_rate,
    round(sum(ecommerce_purchases)::numeric / nullif(sum(sessions), 0), 4)   as purchase_rate
from {{ ref('stg_ga4_traffic_acquisition_daily') }}
group by 1, 2, 3, 4