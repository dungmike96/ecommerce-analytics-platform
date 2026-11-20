{{ config(materialized='incremental', unique_key='order_id') }}

select
    o.order_id,
    -- Gắn chính xác khóa Surrogate Key tương ứng với thông tin của khách hàng tại mốc thời gian mua hàng
    md5(cast(coalesce(cast(u.user_id as varchar), '') || '-' || coalesce(cast(u.dbt_valid_from as varchar), '') as varchar)) as user_key,
    o.user_id,
    o.product_id,
    o.total_amount,
    o.created_at
from {{ source('ecom_source', 'raw_orders') }} o
left join {{ ref('snapshot_users') }} u 
    on o.user_id = u.user_id
    and o.created_at >= u.dbt_valid_from
    and (o.created_at < u.dbt_valid_to or u.dbt_valid_to is null)

{% if is_incremental() %}
  where o.created_at > (select max(created_at) from {{ this }})
{% endif %}
