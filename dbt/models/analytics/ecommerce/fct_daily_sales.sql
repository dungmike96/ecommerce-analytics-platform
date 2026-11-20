{{ config(
    materialized='table'
) }}

-- ============================================================
-- ANALYTICS FACT
-- fct_daily_sales
--
-- Purpose:
--   Daily sales performance by official sales channel.
--
-- Grain:
--   1 row = 1 order_date × 1 sale_channel_id
--
-- Sources:
--   fact_orders
--   dim_channel
--
-- Notes:
--   sale_channel_name comes from the official Nhanh.vn
--   saleChannel mapping maintained in dim_channel.
--
--   sale_channel_group is an internal DWH classification.
--
--   Financial metrics are aggregated directly from fact_orders.
-- ============================================================

WITH orders AS (

    SELECT
        order_id,
        order_date,
        sale_channel_id,

        total_item_lines,
        total_quantity,

        gross_sales_amount,
        discount_amount,
        net_sales_amount,

        estimated_cogs,
        estimated_gross_profit,

        cod_amount,
        business_payment

    FROM {{ ref('fact_orders') }}

),

channels AS (

    SELECT
        sale_channel_id,
        sale_channel_name,
        sale_channel_group,
        is_verified

    FROM {{ ref('dim_channel') }}

),

daily_sales AS (

    SELECT
        o.order_date,
        o.sale_channel_id,

        c.sale_channel_name,
        c.sale_channel_group,
        c.is_verified,

        COUNT(*) AS total_orders,

        COALESCE(
            SUM(o.total_item_lines),
            0
        ) AS total_item_lines,

        COALESCE(
            SUM(o.total_quantity),
            0
        ) AS total_quantity,

        COALESCE(
            SUM(o.gross_sales_amount),
            0
        ) AS gross_sales_amount,

        COALESCE(
            SUM(o.discount_amount),
            0
        ) AS discount_amount,

        COALESCE(
            SUM(o.net_sales_amount),
            0
        ) AS net_sales_amount,

        COALESCE(
            SUM(o.estimated_cogs),
            0
        ) AS estimated_cogs,

        COALESCE(
            SUM(o.estimated_gross_profit),
            0
        ) AS estimated_gross_profit,

        COALESCE(
            SUM(o.cod_amount),
            0
        ) AS cod_amount,

        COALESCE(
            SUM(o.business_payment),
            0
        ) AS business_payment

    FROM orders AS o

    LEFT JOIN channels AS c
        ON o.sale_channel_id = c.sale_channel_id

    GROUP BY
        o.order_date,
        o.sale_channel_id,

        c.sale_channel_name,
        c.sale_channel_group,
        c.is_verified

)

SELECT
    order_date,
    sale_channel_id,

    sale_channel_name,
    sale_channel_group,
    is_verified,

    total_orders,
    total_item_lines,
    total_quantity,

    gross_sales_amount,
    discount_amount,
    net_sales_amount,

    estimated_cogs,
    estimated_gross_profit,

    ROUND(
        net_sales_amount
        / NULLIF(total_orders, 0),
        2
    ) AS avg_order_value,

    ROUND(
        100.0 * estimated_gross_profit
        / NULLIF(net_sales_amount, 0),
        2
    ) AS estimated_gross_margin_pct,

    cod_amount,
    business_payment

FROM daily_sales