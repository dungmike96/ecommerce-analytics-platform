-- ============================================================
-- 15.5.6.1
-- Reconciliation:
-- fct_status_performance <-> fact_orders
--
-- Test passes when query returns 0 rows.
-- ============================================================

WITH warehouse AS (

    SELECT
        COUNT(*) AS total_orders,

        COALESCE(
            SUM(total_quantity),
            0
        ) AS total_quantity,

        COALESCE(
            SUM(gross_sales_amount),
            0
        ) AS gross_sales_amount,

        COALESCE(
            SUM(discount_amount),
            0
        ) AS discount_amount,

        COALESCE(
            SUM(net_sales_amount),
            0
        ) AS net_sales_amount,

        COALESCE(
            SUM(estimated_cogs),
            0
        ) AS estimated_cogs,

        COALESCE(
            SUM(estimated_gross_profit),
            0
        ) AS estimated_gross_profit,

        COALESCE(
            SUM(cod_amount),
            0
        ) AS cod_amount,

        COALESCE(
            SUM(business_payment),
            0
        ) AS business_payment

    FROM {{ ref('fact_orders') }}

),

analytics AS (

    SELECT
        COALESCE(
            SUM(total_orders),
            0
        ) AS total_orders,

        COALESCE(
            SUM(total_quantity),
            0
        ) AS total_quantity,

        COALESCE(
            SUM(gross_sales_amount),
            0
        ) AS gross_sales_amount,

        COALESCE(
            SUM(discount_amount),
            0
        ) AS discount_amount,

        COALESCE(
            SUM(net_sales_amount),
            0
        ) AS net_sales_amount,

        COALESCE(
            SUM(estimated_cogs),
            0
        ) AS estimated_cogs,

        COALESCE(
            SUM(estimated_gross_profit),
            0
        ) AS estimated_gross_profit,

        COALESCE(
            SUM(cod_amount),
            0
        ) AS cod_amount,

        COALESCE(
            SUM(business_payment),
            0
        ) AS business_payment

    FROM {{ ref('fct_status_performance') }}

),

reconciliation AS (

    SELECT
        w.total_orders - a.total_orders
            AS order_difference,

        w.total_quantity - a.total_quantity
            AS quantity_difference,

        w.gross_sales_amount - a.gross_sales_amount
            AS gross_sales_difference,

        w.discount_amount - a.discount_amount
            AS discount_difference,

        w.net_sales_amount - a.net_sales_amount
            AS net_sales_difference,

        w.estimated_cogs - a.estimated_cogs
            AS cogs_difference,

        w.estimated_gross_profit - a.estimated_gross_profit
            AS gross_profit_difference,

        w.cod_amount - a.cod_amount
            AS cod_difference,

        w.business_payment - a.business_payment
            AS business_payment_difference

    FROM warehouse AS w
    CROSS JOIN analytics AS a

)

SELECT *
FROM reconciliation

WHERE
       order_difference <> 0
    OR quantity_difference <> 0
    OR gross_sales_difference <> 0
    OR discount_difference <> 0
    OR net_sales_difference <> 0
    OR cogs_difference <> 0
    OR gross_profit_difference <> 0
    OR cod_difference <> 0
    OR business_payment_difference <> 0