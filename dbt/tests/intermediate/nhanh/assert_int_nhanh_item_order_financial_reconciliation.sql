-- ============================================================
-- RECONCILIATION TEST
-- Item-level financial metrics -> Order-level metrics
--
-- Expected result:
--   0 rows = PASS
--
-- Purpose:
--   Ensure aggregation from int_nhanh_order_items_enriched
--   into int_nhanh_orders_enriched does not alter financial
--   measures.
-- ============================================================

WITH item_totals AS (

    SELECT
        SUM(gross_sales_amount) AS gross_sales_amount,
        SUM(discount_amount) AS discount_amount,
        SUM(net_sales_amount) AS net_sales_amount,
        SUM(estimated_cogs) AS estimated_cogs,
        SUM(estimated_gross_profit) AS estimated_gross_profit

    FROM {{ ref('int_nhanh_order_items_enriched') }}

),

order_totals AS (

    SELECT
        SUM(gross_sales_amount) AS gross_sales_amount,
        SUM(discount_amount) AS discount_amount,
        SUM(net_sales_amount) AS net_sales_amount,
        SUM(estimated_cogs) AS estimated_cogs,
        SUM(estimated_gross_profit) AS estimated_gross_profit

    FROM {{ ref('int_nhanh_orders_enriched') }}

)

SELECT

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

FROM item_totals AS i

CROSS JOIN order_totals AS o

WHERE
       i.gross_sales_amount
           IS DISTINCT FROM o.gross_sales_amount

    OR i.discount_amount
           IS DISTINCT FROM o.discount_amount

    OR i.net_sales_amount
           IS DISTINCT FROM o.net_sales_amount

    OR i.estimated_cogs
           IS DISTINCT FROM o.estimated_cogs

    OR i.estimated_gross_profit
           IS DISTINCT FROM o.estimated_gross_profit