-- Reconciliation:
-- Hai model phải chứa chính xác cùng tập order_id.

with staging as (

    select order_id
    from {{ ref('stg_nhanh_orders') }}

),

intermediate as (

    select order_id
    from {{ ref('int_nhanh_orders_enriched') }}

),

missing_from_intermediate as (

    select order_id
    from staging

    except

    select order_id
    from intermediate

),

unexpected_in_intermediate as (

    select order_id
    from intermediate

    except

    select order_id
    from staging

)

select
    order_id,
    'MISSING_FROM_INTERMEDIATE' as reconciliation_error
from missing_from_intermediate

union all

select
    order_id,
    'UNEXPECTED_IN_INTERMEDIATE' as reconciliation_error
from unexpected_in_intermediate