-- ============================================================
-- 15.2.7.6
-- Singular reconciliation test
--
-- Reconcile:
--   data_schema.fact_orders
--        ->
--   analytics.fct_daily_sales
--
-- Grain:
--   order_date x sale_channel_id
--
-- PASS:
--   query returns 0 rows
-- ============================================================

WITH warehouse AS (

    SELECT
        order_date,
        sale_channel_id,

        COUNT(*) AS total_orders,

        SUM(total_item_lines) AS total_item_lines,
        SUM(total_quantity) AS total_quantity,

        SUM(gross_sales_amount) AS gross_sales_amount,
        SUM(discount_amount) AS discount_amount,
        SUM(net_sales_amount) AS net_sales_amount,

        SUM(estimated_cogs) AS estimated_cogs,
        SUM(estimated_gross_profit) AS estimated_gross_profit,

        SUM(cod_amount) AS cod_amount,
        SUM(business_payment) AS business_payment

    FROM {{ ref('fact_orders') }}

    GROUP BY
        order_date,
        sale_channel_id
),

analytics AS (

    SELECT
        order_date,
        sale_channel_id,

        total_orders,
        total_item_lines,
        total_quantity,

        gross_sales_amount,
        discount_amount,
        net_sales_amount,

        estimated_cogs,
        estimated_gross_profit,

        cod_amount,
        business_payment

    FROM {{ ref('fct_daily_sales') }}

),

mismatches AS (

    SELECT
        COALESCE(w.order_date, a.order_date) AS order_date,
        COALESCE(w.sale_channel_id, a.sale_channel_id) AS sale_channel_id,

        w.total_orders AS warehouse_total_orders,
        a.total_orders AS analytics_total_orders,

        w.total_item_lines AS warehouse_total_item_lines,
        a.total_item_lines AS analytics_total_item_lines,

        w.total_quantity AS warehouse_total_quantity,
        a.total_quantity AS analytics_total_quantity,

        w.gross_sales_amount AS warehouse_gross_sales_amount,
        a.gross_sales_amount AS analytics_gross_sales_amount,

        w.discount_amount AS warehouse_discount_amount,
        a.discount_amount AS analytics_discount_amount,

        w.net_sales_amount AS warehouse_net_sales_amount,
        a.net_sales_amount AS analytics_net_sales_amount,

        w.estimated_cogs AS warehouse_estimated_cogs,
        a.estimated_cogs AS analytics_estimated_cogs,

        w.estimated_gross_profit AS warehouse_estimated_gross_profit,
        a.estimated_gross_profit AS analytics_estimated_gross_profit,

        w.cod_amount AS warehouse_cod_amount,
        a.cod_amount AS analytics_cod_amount,

        w.business_payment AS warehouse_business_payment,
        a.business_payment AS analytics_business_payment

    FROM warehouse AS w

    FULL OUTER JOIN analytics AS a
        ON w.order_date = a.order_date
       AND w.sale_channel_id = a.sale_channel_id

    WHERE
           w.order_date IS NULL
        OR a.order_date IS NULL

        OR w.total_orders
            IS DISTINCT FROM a.total_orders

        OR w.total_item_lines
            IS DISTINCT FROM a.total_item_lines

        OR w.total_quantity
            IS DISTINCT FROM a.total_quantity

        OR w.gross_sales_amount
            IS DISTINCT FROM a.gross_sales_amount

        OR w.discount_amount
            IS DISTINCT FROM a.discount_amount

        OR w.net_sales_amount
            IS DISTINCT FROM a.net_sales_amount

        OR w.estimated_cogs
            IS DISTINCT FROM a.estimated_cogs

        OR w.estimated_gross_profit
            IS DISTINCT FROM a.estimated_gross_profit

        OR w.cod_amount
            IS DISTINCT FROM a.cod_amount

        OR w.business_payment
            IS DISTINCT FROM a.business_payment
)

SELECT *
FROM mismatches