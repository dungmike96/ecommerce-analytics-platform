-- ============================================================
-- 13.4.4.6
-- RECONCILIATION TEST
-- Item line count / quantity -> Order level
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

        COUNT(*) AS total_item_lines,

        SUM(quantity) AS total_quantity

    FROM {{ ref('int_nhanh_order_items_enriched') }}

    GROUP BY order_id

),

orders AS (

    SELECT
        order_id,
        total_item_lines,
        total_quantity

    FROM {{ ref('int_nhanh_orders_enriched') }}

    WHERE has_items = TRUE

)

SELECT
    o.order_id,

    i.total_item_lines
        AS item_total_item_lines,

    o.total_item_lines
        AS order_total_item_lines,

    i.total_quantity
        AS item_total_quantity,

    o.total_quantity
        AS order_total_quantity

FROM orders AS o

LEFT JOIN item_by_order AS i
    ON o.order_id = i.order_id

WHERE
       i.order_id IS NULL

    OR i.total_item_lines
           IS DISTINCT FROM o.total_item_lines

    OR i.total_quantity
           IS DISTINCT FROM o.total_quantity