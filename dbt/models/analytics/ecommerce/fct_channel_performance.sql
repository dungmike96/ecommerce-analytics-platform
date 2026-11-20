{{ config(
    materialized='table'
) }}

-- ============================================================
-- ANALYTICS FACT
-- fct_channel_performance
--
-- Purpose:
--   Overall sales performance by official sales channel.
--
-- Grain:
--   1 row = 1 sale_channel_id
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
--
--   estimated_gross_profit is an estimated gross-profit metric,
--   not final net profit.
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
        business_payment,

        has_zero_cost_items,
        has_net_formula_mismatch

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

channel_performance AS (

    SELECT
        o.sale_channel_id,

        c.sale_channel_name,
        c.sale_channel_group,
        c.is_verified,

        -- ----------------------------------------------------
        -- Order volume
        -- ----------------------------------------------------

        COUNT(*) AS total_orders,

        COALESCE(
            SUM(o.total_item_lines),
            0
        ) AS total_item_lines,

        COALESCE(
            SUM(o.total_quantity),
            0
        ) AS total_quantity,

        -- ----------------------------------------------------
        -- Activity period
        -- ----------------------------------------------------

        MIN(o.order_date) AS first_order_date,

        MAX(o.order_date) AS last_order_date,

        COUNT(
            DISTINCT o.order_date
        ) AS active_days,

        -- ----------------------------------------------------
        -- Sales
        -- ----------------------------------------------------

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

        -- ----------------------------------------------------
        -- Estimated profitability
        -- ----------------------------------------------------

        COALESCE(
            SUM(o.estimated_cogs),
            0
        ) AS estimated_cogs,

        COALESCE(
            SUM(o.estimated_gross_profit),
            0
        ) AS estimated_gross_profit,

        -- ----------------------------------------------------
        -- Payment
        -- ----------------------------------------------------

        COALESCE(
            SUM(o.cod_amount),
            0
        ) AS cod_amount,

        COALESCE(
            SUM(o.business_payment),
            0
        ) AS business_payment,

        -- ----------------------------------------------------
        -- Data quality
        -- ----------------------------------------------------

        COUNT(*) FILTER (
            WHERE o.has_zero_cost_items = TRUE
        ) AS zero_cost_orders,

        COUNT(*) FILTER (
            WHERE o.has_net_formula_mismatch = TRUE
        ) AS net_formula_mismatch_orders

    FROM orders AS o

    LEFT JOIN channels AS c
        ON o.sale_channel_id = c.sale_channel_id

    GROUP BY
        o.sale_channel_id,
        c.sale_channel_name,
        c.sale_channel_group,
        c.is_verified

),

final AS (

    SELECT
        -- ----------------------------------------------------
        -- Dimension
        -- ----------------------------------------------------

        sale_channel_id,
        sale_channel_name,
        sale_channel_group,
        is_verified,

        -- ----------------------------------------------------
        -- Order volume
        -- ----------------------------------------------------

        total_orders,
        total_item_lines,
        total_quantity,

        -- ----------------------------------------------------
        -- Activity period
        -- ----------------------------------------------------

        first_order_date,
        last_order_date,
        active_days,

        -- ----------------------------------------------------
        -- Financial base metrics
        -- ----------------------------------------------------

        gross_sales_amount,
        discount_amount,
        net_sales_amount,

        estimated_cogs,
        estimated_gross_profit,

        -- ----------------------------------------------------
        -- Derived commercial metrics
        -- ----------------------------------------------------

        ROUND(
            net_sales_amount
            / NULLIF(total_orders, 0),
            2
        ) AS avg_order_value,

        ROUND(
            total_quantity::numeric
            / NULLIF(total_orders, 0),
            2
        ) AS avg_quantity_per_order,

        ROUND(
            100.0 * discount_amount
            / NULLIF(gross_sales_amount, 0),
            2
        ) AS discount_rate_pct,

        ROUND(
            100.0 * estimated_gross_profit
            / NULLIF(net_sales_amount, 0),
            2
        ) AS estimated_gross_margin_pct,

        -- ----------------------------------------------------
        -- Payment metrics
        -- ----------------------------------------------------

        cod_amount,
        business_payment,

        ROUND(
            100.0 * cod_amount
            / NULLIF(net_sales_amount, 0),
            2
        ) AS cod_to_net_sales_pct,

        ROUND(
            100.0 * business_payment
            / NULLIF(net_sales_amount, 0),
            2
        ) AS business_payment_to_net_sales_pct,

        -- ----------------------------------------------------
        -- Data quality metrics
        -- ----------------------------------------------------

        zero_cost_orders,
        net_formula_mismatch_orders

    FROM channel_performance

)

SELECT *
FROM final