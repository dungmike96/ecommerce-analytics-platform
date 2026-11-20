-- ============================================================
-- 15.7.3D
-- FINAL ANALYTICS SALES RECONCILIATION
--
-- Purpose:
--   Ensure the main analytics fact tables reconcile back
--   to data_schema.fact_orders.
--
-- Models checked:
--   fact_orders
--       ↓
--   fct_daily_sales
--   fct_channel_performance
--   fct_status_performance
--
-- Metrics checked:
--   1. total_orders
--   2. gross_sales_amount
--   3. discount_amount
--   4. net_sales_amount
--   5. estimated_cogs
--   6. estimated_gross_profit
--
-- dbt singular test rule:
--   0 rows = PASS
--   >= 1 row = FAIL
-- ============================================================

WITH fact AS (

    SELECT
        COUNT(*) AS total_orders,

        COALESCE(SUM(gross_sales_amount), 0)
            AS gross_sales_amount,

        COALESCE(SUM(discount_amount), 0)
            AS discount_amount,

        COALESCE(SUM(net_sales_amount), 0)
            AS net_sales_amount,

        COALESCE(SUM(estimated_cogs), 0)
            AS estimated_cogs,

        COALESCE(SUM(estimated_gross_profit), 0)
            AS estimated_gross_profit

    FROM {{ ref('fact_orders') }}

),

daily AS (

    SELECT
        COALESCE(SUM(total_orders), 0)
            AS total_orders,

        COALESCE(SUM(gross_sales_amount), 0)
            AS gross_sales_amount,

        COALESCE(SUM(discount_amount), 0)
            AS discount_amount,

        COALESCE(SUM(net_sales_amount), 0)
            AS net_sales_amount,

        COALESCE(SUM(estimated_cogs), 0)
            AS estimated_cogs,

        COALESCE(SUM(estimated_gross_profit), 0)
            AS estimated_gross_profit

    FROM {{ ref('fct_daily_sales') }}

),

channel AS (

    SELECT
        COALESCE(SUM(total_orders), 0)
            AS total_orders,

        COALESCE(SUM(gross_sales_amount), 0)
            AS gross_sales_amount,

        COALESCE(SUM(discount_amount), 0)
            AS discount_amount,

        COALESCE(SUM(net_sales_amount), 0)
            AS net_sales_amount,

        COALESCE(SUM(estimated_cogs), 0)
            AS estimated_cogs,

        COALESCE(SUM(estimated_gross_profit), 0)
            AS estimated_gross_profit

    FROM {{ ref('fct_channel_performance') }}

),

status AS (

    SELECT
        COALESCE(SUM(total_orders), 0)
            AS total_orders,

        COALESCE(SUM(gross_sales_amount), 0)
            AS gross_sales_amount,

        COALESCE(SUM(discount_amount), 0)
            AS discount_amount,

        COALESCE(SUM(net_sales_amount), 0)
            AS net_sales_amount,

        COALESCE(SUM(estimated_cogs), 0)
            AS estimated_cogs,

        COALESCE(SUM(estimated_gross_profit), 0)
            AS estimated_gross_profit

    FROM {{ ref('fct_status_performance') }}

),

reconciliation AS (

    SELECT
        f.total_orders AS fact_total_orders,

        d.total_orders AS daily_total_orders,
        c.total_orders AS channel_total_orders,
        s.total_orders AS status_total_orders,

        f.gross_sales_amount AS fact_gross_sales,
        d.gross_sales_amount AS daily_gross_sales,
        c.gross_sales_amount AS channel_gross_sales,
        s.gross_sales_amount AS status_gross_sales,

        f.discount_amount AS fact_discount,
        d.discount_amount AS daily_discount,
        c.discount_amount AS channel_discount,
        s.discount_amount AS status_discount,

        f.net_sales_amount AS fact_net_sales,
        d.net_sales_amount AS daily_net_sales,
        c.net_sales_amount AS channel_net_sales,
        s.net_sales_amount AS status_net_sales,

        f.estimated_cogs AS fact_cogs,
        d.estimated_cogs AS daily_cogs,
        c.estimated_cogs AS channel_cogs,
        s.estimated_cogs AS status_cogs,

        f.estimated_gross_profit AS fact_gross_profit,
        d.estimated_gross_profit AS daily_gross_profit,
        c.estimated_gross_profit AS channel_gross_profit,
        s.estimated_gross_profit AS status_gross_profit

    FROM fact AS f
    CROSS JOIN daily AS d
    CROSS JOIN channel AS c
    CROSS JOIN status AS s

)

SELECT *

FROM reconciliation

WHERE

    -- ORDER COUNT
    fact_total_orders IS DISTINCT FROM daily_total_orders
    OR fact_total_orders IS DISTINCT FROM channel_total_orders
    OR fact_total_orders IS DISTINCT FROM status_total_orders

    -- GROSS SALES
    OR fact_gross_sales IS DISTINCT FROM daily_gross_sales
    OR fact_gross_sales IS DISTINCT FROM channel_gross_sales
    OR fact_gross_sales IS DISTINCT FROM status_gross_sales

    -- DISCOUNT
    OR fact_discount IS DISTINCT FROM daily_discount
    OR fact_discount IS DISTINCT FROM channel_discount
    OR fact_discount IS DISTINCT FROM status_discount

    -- NET SALES
    OR fact_net_sales IS DISTINCT FROM daily_net_sales
    OR fact_net_sales IS DISTINCT FROM channel_net_sales
    OR fact_net_sales IS DISTINCT FROM status_net_sales

    -- COGS
    OR fact_cogs IS DISTINCT FROM daily_cogs
    OR fact_cogs IS DISTINCT FROM channel_cogs
    OR fact_cogs IS DISTINCT FROM status_cogs

    -- GROSS PROFIT
    OR fact_gross_profit IS DISTINCT FROM daily_gross_profit
    OR fact_gross_profit IS DISTINCT FROM channel_gross_profit
    OR fact_gross_profit IS DISTINCT FROM status_gross_profit