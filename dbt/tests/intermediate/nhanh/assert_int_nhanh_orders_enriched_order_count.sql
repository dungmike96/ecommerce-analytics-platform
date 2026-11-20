-- Reconciliation:
-- stg_nhanh_orders -> int_nhanh_orders_enriched
--
-- Grain của cả hai model: 1 row / order_id
-- Test FAIL nếu số lượng order khác nhau.

with staging as (

    select count(*) as total_orders
    from {{ ref('stg_nhanh_orders') }}

),

intermediate as (

    select count(*) as total_orders
    from {{ ref('int_nhanh_orders_enriched') }}

)

select
    staging.total_orders as staging_orders,
    intermediate.total_orders as intermediate_orders,
    intermediate.total_orders - staging.total_orders as difference

from staging
cross join intermediate

where staging.total_orders <> intermediate.total_orders