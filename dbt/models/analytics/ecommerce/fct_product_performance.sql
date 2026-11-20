{{ config(
    materialized='table'
) }}

with product_metrics as (

    select
        product_id,

        count(*) as item_lines,
        count(distinct order_id) as order_count,

        sum(quantity) as total_quantity,

        sum(gross_sales_amount) as gross_sales_amount,
        sum(discount_amount) as discount_amount,
        sum(net_sales_amount) as net_sales_amount,

        sum(estimated_cogs) as estimated_cogs,
        sum(estimated_gross_profit) as estimated_gross_profit

    from {{ ref('fact_order_items') }}

    group by product_id
),

final as (

    select
        m.product_id,
        p.product_name,

        m.item_lines,
        m.order_count,
        m.total_quantity,

        m.gross_sales_amount,
        m.discount_amount,
        m.net_sales_amount,

        m.estimated_cogs,
        m.estimated_gross_profit,

        round(
            100.0 * m.estimated_gross_profit
            / nullif(m.net_sales_amount, 0),
            2
        ) as estimated_gross_margin_pct,

        round(
            m.net_sales_amount
            / nullif(m.total_quantity, 0),
            2
        ) as avg_selling_price,

        round(
            m.total_quantity
            / nullif(m.order_count, 0),
            2
        ) as avg_quantity_per_order

    from product_metrics as m

    left join {{ ref('dim_product') }} as p
        on m.product_id = p.product_id

)

select *
from final