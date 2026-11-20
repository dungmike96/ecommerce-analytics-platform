-- ============================================================
-- 15.3.6.1
-- Reconciliation:
-- fact_order_items -> fct_product_performance
--
-- Grain:
--   1 row = 1 product_id
--
-- PASS:
--   query returns 0 rows
-- ============================================================

WITH fact AS (

    SELECT
        product_id,

        COUNT(*) AS item_lines,
        COUNT(DISTINCT order_id) AS order_count,
        SUM(quantity) AS total_quantity,

        SUM(gross_sales_amount) AS gross_sales_amount,
        SUM(discount_amount) AS discount_amount,
        SUM(net_sales_amount) AS net_sales_amount,

        SUM(estimated_cogs) AS estimated_cogs,
        SUM(estimated_gross_profit) AS estimated_gross_profit

    FROM {{ ref('fact_order_items') }}

    GROUP BY product_id
),

analytics AS (

    SELECT
        product_id,

        item_lines,
        order_count,
        total_quantity,

        gross_sales_amount,
        discount_amount,
        net_sales_amount,

        estimated_cogs,
        estimated_gross_profit

    FROM {{ ref('fct_product_performance') }}
),

mismatches AS (

    SELECT
        COALESCE(f.product_id, a.product_id) AS product_id,

        f.item_lines AS fact_item_lines,
        a.item_lines AS analytics_item_lines,

        f.order_count AS fact_order_count,
        a.order_count AS analytics_order_count,

        f.total_quantity AS fact_total_quantity,
        a.total_quantity AS analytics_total_quantity,

        f.gross_sales_amount AS fact_gross_sales_amount,
        a.gross_sales_amount AS analytics_gross_sales_amount,

        f.discount_amount AS fact_discount_amount,
        a.discount_amount AS analytics_discount_amount,

        f.net_sales_amount AS fact_net_sales_amount,
        a.net_sales_amount AS analytics_net_sales_amount,

        f.estimated_cogs AS fact_estimated_cogs,
        a.estimated_cogs AS analytics_estimated_cogs,

        f.estimated_gross_profit AS fact_estimated_gross_profit,
        a.estimated_gross_profit AS analytics_estimated_gross_profit

    FROM fact AS f

    FULL OUTER JOIN analytics AS a
        ON f.product_id = a.product_id

    WHERE
           f.product_id IS NULL
        OR a.product_id IS NULL

        OR f.item_lines
            IS DISTINCT FROM a.item_lines

        OR f.order_count
            IS DISTINCT FROM a.order_count

        OR f.total_quantity
            IS DISTINCT FROM a.total_quantity

        OR f.gross_sales_amount
            IS DISTINCT FROM a.gross_sales_amount

        OR f.discount_amount
            IS DISTINCT FROM a.discount_amount

        OR f.net_sales_amount
            IS DISTINCT FROM a.net_sales_amount

        OR f.estimated_cogs
            IS DISTINCT FROM a.estimated_cogs

        OR f.estimated_gross_profit
            IS DISTINCT FROM a.estimated_gross_profit
)

SELECT *
FROM mismatches