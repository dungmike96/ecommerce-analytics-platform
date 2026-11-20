-- ============================================================
-- 15.3.6.2
-- Validate derived product metrics
--
-- Checks:
--   estimated_gross_margin_pct
--   avg_selling_price
--   avg_quantity_per_order
--
-- PASS:
--   query returns 0 rows
-- ============================================================

SELECT
    product_id,

    estimated_gross_margin_pct,

    ROUND(
        100.0 * estimated_gross_profit
        / NULLIF(net_sales_amount, 0),
        2
    ) AS expected_gross_margin_pct,

    avg_selling_price,

    ROUND(
        net_sales_amount
        / NULLIF(total_quantity, 0),
        2
    ) AS expected_avg_selling_price,

    avg_quantity_per_order,

    ROUND(
        total_quantity
        / NULLIF(order_count, 0),
        2
    ) AS expected_avg_quantity_per_order

FROM {{ ref('fct_product_performance') }}

WHERE
       estimated_gross_margin_pct IS DISTINCT FROM
       ROUND(
           100.0 * estimated_gross_profit
           / NULLIF(net_sales_amount, 0),
           2
       )

    OR avg_selling_price IS DISTINCT FROM
       ROUND(
           net_sales_amount
           / NULLIF(total_quantity, 0),
           2
       )

    OR avg_quantity_per_order IS DISTINCT FROM
       ROUND(
           total_quantity
           / NULLIF(order_count, 0),
           2
       )