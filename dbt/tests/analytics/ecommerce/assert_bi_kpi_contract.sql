-- ============================================================
-- 15.8.2.3C
-- BI KPI CONTRACT
--
-- Purpose:
--   Protect the canonical BI KPI contract between
--   data_schema.fact_orders and analytics.fct_daily_sales.
--
-- Canonical financial source of truth:
--   fact_orders
--
-- Expected:
--   Query returns 0 rows.
-- ============================================================

WITH fact AS (

    SELECT
        COUNT(*) AS total_orders,
        SUM(total_quantity) AS total_quantity,
        SUM(gross_sales_amount) AS gross_sales_amount,
        SUM(discount_amount) AS discount_amount,
        SUM(net_sales_amount) AS net_sales_amount,
        SUM(estimated_cogs) AS estimated_cogs,
        SUM(estimated_gross_profit) AS estimated_gross_profit,
        SUM(cod_amount) AS cod_amount,
        SUM(business_payment) AS business_payment

    FROM {{ ref('fact_orders') }}

),

daily AS (

    SELECT
        SUM(total_orders) AS total_orders,
        SUM(total_quantity) AS total_quantity,
        SUM(gross_sales_amount) AS gross_sales_amount,
        SUM(discount_amount) AS discount_amount,
        SUM(net_sales_amount) AS net_sales_amount,
        SUM(estimated_cogs) AS estimated_cogs,
        SUM(estimated_gross_profit) AS estimated_gross_profit,
        SUM(cod_amount) AS cod_amount,
        SUM(business_payment) AS business_payment

    FROM {{ ref('fct_daily_sales') }}

),

reconciliation AS (

    SELECT

        fact.total_orders - daily.total_orders
            AS total_orders_diff,

        fact.total_quantity - daily.total_quantity
            AS total_quantity_diff,

        fact.gross_sales_amount - daily.gross_sales_amount
            AS gross_sales_diff,

        fact.discount_amount - daily.discount_amount
            AS discount_diff,

        fact.net_sales_amount - daily.net_sales_amount
            AS net_sales_diff,

        fact.estimated_cogs - daily.estimated_cogs
            AS estimated_cogs_diff,

        fact.estimated_gross_profit - daily.estimated_gross_profit
            AS estimated_gross_profit_diff,

        fact.cod_amount - daily.cod_amount
            AS cod_amount_diff,

        fact.business_payment - daily.business_payment
            AS business_payment_diff

    FROM fact
    CROSS JOIN daily

)

SELECT *
FROM reconciliation

WHERE ABS(total_orders_diff) > 0
   OR ABS(total_quantity_diff) > 0.01
   OR ABS(gross_sales_diff) > 0.01
   OR ABS(discount_diff) > 0.01
   OR ABS(net_sales_diff) > 0.01
   OR ABS(estimated_cogs_diff) > 0.01
   OR ABS(estimated_gross_profit_diff) > 0.01
   OR ABS(cod_amount_diff) > 0.01
   OR ABS(business_payment_diff) > 0.01