{{ config(
    materialized='table'
) }}

-- ============================================================
-- ANALYTICS FACT
-- fct_status_performance
--
-- Purpose:
--   Overall order and financial performance by official
--   Nhanh.vn order status.
--
-- Grain:
--   1 row = 1 status_id
--
-- Sources:
--   fact_orders
--   dim_status
--
-- Notes:
--   status_name comes from the official Nhanh.vn API
--   status mapping maintained in dim_status.
--
--   Financial metrics are aggregated directly from fact_orders.
--
--   estimated_gross_profit is not final net profit because
--   marketplace fees and other operating costs are not yet
--   fully available.
-- ============================================================

WITH orders AS (

    SELECT
        order_id,
        order_date,
        status_id,

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

statuses AS (

    SELECT
        status_id,
        status_name,
        status_mapping_state,
        is_verified

    FROM {{ ref('dim_status') }}

),

status_performance AS (

    SELECT
        o.status_id,

        s.status_name,
        s.status_mapping_state,
        s.is_verified,

        COUNT(*) AS total_orders,

        COALESCE(
            SUM(o.total_quantity),
            0
        ) AS total_quantity,

        MIN(o.order_date) AS first_order_date,
        MAX(o.order_date) AS last_order_date,

        COUNT(
            DISTINCT o.order_date
        ) AS active_days,

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
        ) AS business_payment,

        COUNT(*) FILTER (
            WHERE o.net_sales_amount = 0
        ) AS zero_net_sales_orders,

        COUNT(*) FILTER (
            WHERE o.estimated_gross_profit < 0
        ) AS negative_profit_orders,

        COUNT(*) FILTER (
            WHERE o.has_zero_cost_items = TRUE
        ) AS zero_cost_orders,

        COUNT(*) FILTER (
            WHERE o.has_net_formula_mismatch = TRUE
        ) AS net_formula_mismatch_orders

    FROM orders AS o

    LEFT JOIN statuses AS s
        ON o.status_id = s.status_id

    GROUP BY
        o.status_id,
        s.status_name,
        s.status_mapping_state,
        s.is_verified

)

SELECT
    status_id,

    status_name,
    status_mapping_state,
    is_verified,

    total_orders,
    total_quantity,

    first_order_date,
    last_order_date,
    active_days,

    gross_sales_amount,
    discount_amount,
    net_sales_amount,

    estimated_cogs,
    estimated_gross_profit,

    ROUND(
        100.0 * estimated_gross_profit
        / NULLIF(net_sales_amount, 0),
        2
    ) AS estimated_gross_margin_pct,

    cod_amount,
    business_payment,

    zero_net_sales_orders,
    negative_profit_orders,
    zero_cost_orders,
    net_formula_mismatch_orders

FROM status_performance