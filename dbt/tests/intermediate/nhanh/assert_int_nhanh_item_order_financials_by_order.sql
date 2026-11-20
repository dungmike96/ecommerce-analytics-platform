-- ============================================================
-- 13.4.4.5
-- RECONCILIATION TEST
-- Item-level -> Order-level financial metrics BY ORDER
--
-- Grain checked:
--   1 row = 1 order_id
--
-- Expected:
--   0 rows = PASS
-- ============================================================

WITH item_by_order AS (

    SELECT
        order_id,

        SUM(gross_sales_amount)
            AS gross_sales_amount,

        SUM(discount_amount)
            AS discount_amount,

        SUM(net_sales_amount)
            AS net_sales_amount,

        SUM(estimated_cogs)
            AS estimated_cogs,

        SUM(estimated_gross_profit)
            AS estimated_gross_profit

    FROM {{ ref('int_nhanh_order_items_enriched') }}

    GROUP BY order_id

),

orders AS (

    SELECT
        order_id,

        gross_sales_amount,
        discount_amount,
        net_sales_amount,
        estimated_cogs,
        estimated_gross_profit

    FROM {{ ref('int_nhanh_orders_enriched') }}

    WHERE has_items = TRUE

)

SELECT
    o.order_id,

    i.gross_sales_amount
        AS item_gross_sales_amount,

    o.gross_sales_amount
        AS order_gross_sales_amount,

    i.discount_amount
        AS item_discount_amount,

    o.discount_amount
        AS order_discount_amount,

    i.net_sales_amount
        AS item_net_sales_amount,

    o.net_sales_amount
        AS order_net_sales_amount,

    i.estimated_cogs
        AS item_estimated_cogs,

    o.estimated_cogs
        AS order_estimated_cogs,

    i.estimated_gross_profit
        AS item_estimated_gross_profit,

    o.estimated_gross_profit
        AS order_estimated_gross_profit

FROM orders AS o

LEFT JOIN item_by_order AS i
    ON o.order_id = i.order_id

WHERE
       i.order_id IS NULL

    OR i.gross_sales_amount
           IS DISTINCT FROM o.gross_sales_amount

    OR i.discount_amount
           IS DISTINCT FROM o.discount_amount

    OR i.net_sales_amount
           IS DISTINCT FROM o.net_sales_amount

    OR i.estimated_cogs
           IS DISTINCT FROM o.estimated_cogs

    OR i.estimated_gross_profit
           IS DISTINCT FROM o.estimated_gross_profit