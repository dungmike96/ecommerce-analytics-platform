{{ config(materialized='table') }}

select
    md5(cast(coalesce(cast(user_id as varchar), '') || '-' || coalesce(cast(dbt_valid_from as varchar), '') as varchar)) as user_key,
    user_id,
    email,
    user_name,
    shipping_address,
    user_tier,
    dbt_valid_from as valid_from,
    dbt_valid_to as valid_to,
    case when dbt_valid_to is null then true else false end as is_current
from {{ ref('snapshot_users') }}
