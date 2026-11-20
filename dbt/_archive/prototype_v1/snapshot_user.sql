{% snapshot snapshot_users %}

{{
    config(
      target_database='data_center',
      target_schema='warehouse',
      unique_key='user_id',
      strategy='timestamp',
      updated_at='updated_at',
      invalidate_hard_deletes=True
    )
}}

select 
    user_id,
    email,
    user_name,
    shipping_address,
    user_tier,
    updated_at
from {{ source('ecom_source', 'raw_users') }}

{% endsnapshot %}
