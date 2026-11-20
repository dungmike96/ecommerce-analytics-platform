-- Reconciliation:
-- int_nhanh_orders_enriched -> int_nhanh_orders_classified
--
-- Classification chỉ bổ sung business classification.
-- Không được thay đổi grain hoặc số lượng order.

with enriched as (

    select count(*) as total_orders
    from {{ ref('int_nhanh_orders_enriched') }}

),

classified as (

    select count(*) as total_orders
    from {{ ref('int_nhanh_orders_classified') }}

)

select
    enriched.total_orders as enriched_orders,
    classified.total_orders as classified_orders,
    classified.total_orders - enriched.total_orders as difference

from enriched
cross join classified

where enriched.total_orders <> classified.total_orders