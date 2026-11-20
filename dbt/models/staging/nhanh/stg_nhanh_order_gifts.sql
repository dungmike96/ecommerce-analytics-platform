-- ============================================================
-- STAGING: NHANH.VN ORDER GIFTS
-- Grain: 1 row = 1 gift line inside an order
-- Source: raw.nhanh_orders -> api_response.gifts[]
-- ============================================================

with source as (

    select
        order_id,
        api_response

    from {{ source('nhanh', 'nhanh_orders') }}

),

flattened_gifts as (

    select
        s.order_id,

        -- Position of the gift inside gifts[]
        g.gift_line_number,

        g.gift

    from source as s

    cross join lateral jsonb_array_elements(
        s.api_response -> 'gifts'
    ) with ordinality as g(gift, gift_line_number)

    where jsonb_typeof(
        s.api_response -> 'gifts'
    ) = 'array'

),

extracted as (

    select

        -- ====================================================
        -- GRAIN / IDENTIFIERS
        -- ====================================================

        order_id::bigint
            as order_id,

        gift_line_number::integer
            as gift_line_number,

        nullif(
            gift ->> 'orderProductId',
            ''
        )::bigint
            as order_product_id,

        nullif(
            gift ->> 'productId',
            ''
        )::bigint
            as product_id,


        -- ====================================================
        -- GIFT INFORMATION
        -- ====================================================

        nullif(
            gift ->> 'name',
            ''
        ) as gift_name,

        nullif(
            gift ->> 'quantity',
            ''
        )::numeric
            as quantity,

        nullif(
            gift ->> 'price',
            ''
        )::numeric
            as price

    from flattened_gifts

),

final as (

    select *
    from extracted

)

select *
from final