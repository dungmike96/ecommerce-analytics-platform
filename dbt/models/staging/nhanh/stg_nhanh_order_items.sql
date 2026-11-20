-- ============================================================
-- STAGING: NHANH.VN ORDER ITEMS
-- Grain: 1 row = 1 order product line
-- Source: raw.nhanh_orders -> api_response.products[]
-- ============================================================

with source as (

    select
        order_id,
        api_response

    from {{ source('nhanh', 'nhanh_orders') }}

),

flattened_products as (

    select
        s.order_id,
        p.product

    from source as s

    cross join lateral jsonb_array_elements(
        s.api_response -> 'products'
    ) as p(product)

    where jsonb_typeof(
        s.api_response -> 'products'
    ) = 'array'

),

extracted as (

    select

        -- ====================================================
        -- IDENTIFIERS
        -- ====================================================

        order_id::bigint
            as order_id,

        nullif(
            product ->> 'orderProductId',
            ''
        )::bigint
            as order_product_id,

        nullif(
            product ->> 'productId',
            ''
        )::bigint
            as product_id,

        nullif(
            product ->> 'typeId',
            ''
        )::integer
            as product_type_id,


        -- ====================================================
        -- PRODUCT INFORMATION
        -- ====================================================

        nullif(
            product ->> 'code',
            ''
        ) as product_code,

        nullif(
            product ->> 'name',
            ''
        ) as product_name,


        -- ====================================================
        -- QUANTITY / PRICE
        -- ====================================================

        nullif(
            product ->> 'quantity',
            ''
        )::numeric
            as quantity,

        nullif(
            product ->> 'price',
            ''
        )::numeric
            as unit_price,

        nullif(
            product ->> 'originalPrice',
            ''
        )::numeric
            as original_price,

        nullif(
            product ->> 'priceAfterVAT',
            ''
        )::numeric
            as price_after_vat,


        -- ====================================================
        -- DISCOUNT
        -- ====================================================

        nullif(
            product ->> 'discount',
            ''
        )::numeric
            as unit_discount,

        nullif(
            product ->> 'discountAmount',
            ''
        )::numeric
            as discount_amount,


        -- ====================================================
        -- COST / VAT / LINE TOTAL
        -- ====================================================

        nullif(
            product ->> 'avgCost',
            ''
        )::numeric
            as avg_cost,

        nullif(
            product ->> 'vatPercent',
            ''
        )::numeric
            as vat_percent,

        nullif(
            product ->> 'totalAmount',
            ''
        )::numeric
            as total_amount

    from flattened_products

),

final as (

    select *
    from extracted

)

select *
from final