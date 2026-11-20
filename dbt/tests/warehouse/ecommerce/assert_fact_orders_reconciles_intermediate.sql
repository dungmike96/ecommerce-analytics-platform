-- ============================================================
-- 14.6.6.4
-- WAREHOUSE RECONCILIATION TEST
--
-- int_nhanh_orders_classified -> fact_orders
--
-- Expected:
--   0 rows = PASS
--
-- Protects:
--   - exact order_id set
--   - financial measures by order
-- ============================================================

WITH intermediate AS (

    SELECT
        order_id,
        gross_sales_amount,
        discount_amount,
        net_sales_amount,
        estimated_cogs,
        estimated_gross_profit,
        adjusted_revenue_amount

    FROM {{ ref('int_nhanh_orders_classified') }}

),

warehouse AS (

    SELECT
        order_id,
        gross_sales_amount,
        discount_amount,
        net_sales_amount,
        estimated_cogs,
        estimated_gross_profit,
        adjusted_revenue_amount
    FROM {{ ref('fact_orders') }}

),

reconciliation AS (

    SELECT
        COALESCE(i.order_id, w.order_id) AS order_id,

        i.order_id AS intermediate_order_id,
        w.order_id AS warehouse_order_id,

        i.gross_sales_amount AS intermediate_gross_sales,
        w.gross_sales_amount AS warehouse_gross_sales,

        i.discount_amount AS intermediate_discount,
        w.discount_amount AS warehouse_discount,

        i.net_sales_amount AS intermediate_net_sales,
        w.net_sales_amount AS warehouse_net_sales,

        i.estimated_cogs AS intermediate_cogs,
        w.estimated_cogs AS warehouse_cogs,

        i.estimated_gross_profit AS intermediate_gross_profit,
        w.estimated_gross_profit AS warehouse_gross_profit,
        i.adjusted_revenue_amount AS intermediate_adjusted_revenue,
        w.adjusted_revenue_amount AS warehouse_adjusted_revenue

    FROM intermediate AS i

    FULL OUTER JOIN warehouse AS w
        ON i.order_id = w.order_id

)

SELECT *
FROM reconciliation

WHERE
       intermediate_order_id IS NULL
    OR warehouse_order_id IS NULL

    OR intermediate_gross_sales
        IS DISTINCT FROM warehouse_gross_sales

    OR intermediate_discount
        IS DISTINCT FROM warehouse_discount

    OR intermediate_net_sales
        IS DISTINCT FROM warehouse_net_sales

    OR intermediate_cogs
        IS DISTINCT FROM warehouse_cogs

    OR intermediate_gross_profit
        IS DISTINCT FROM warehouse_gross_profit
    OR intermediate_adjusted_revenue
        IS DISTINCT FROM warehouse_adjusted_revenue