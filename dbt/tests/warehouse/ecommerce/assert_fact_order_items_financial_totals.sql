-- ============================================================
-- Financial aggregate reconciliation
--
-- int_nhanh_order_items_enriched -> fact_order_items
--
-- Expected result: 0 rows
-- ============================================================

WITH intermediate AS (

    SELECT
        COUNT(*) AS total_rows,
        SUM(quantity) AS total_quantity,
        SUM(gross_sales_amount) AS gross_sales_amount,
        SUM(discount_amount) AS discount_amount,
        SUM(net_sales_amount) AS net_sales_amount,
        SUM(estimated_cogs) AS estimated_cogs,
        SUM(estimated_gross_profit) AS estimated_gross_profit

    FROM {{ ref('int_nhanh_order_items_enriched') }}

),

fact AS (

    SELECT
        COUNT(*) AS total_rows,
        SUM(quantity) AS total_quantity,
        SUM(gross_sales_amount) AS gross_sales_amount,
        SUM(discount_amount) AS discount_amount,
        SUM(net_sales_amount) AS net_sales_amount,
        SUM(estimated_cogs) AS estimated_cogs,
        SUM(estimated_gross_profit) AS estimated_gross_profit

    FROM {{ ref('fact_order_items') }}

)

SELECT
    i.total_rows AS intermediate_rows,
    f.total_rows AS fact_rows,

    i.total_quantity AS intermediate_quantity,
    f.total_quantity AS fact_quantity,

    i.gross_sales_amount AS intermediate_gross_sales,
    f.gross_sales_amount AS fact_gross_sales,

    i.discount_amount AS intermediate_discount,
    f.discount_amount AS fact_discount,

    i.net_sales_amount AS intermediate_net_sales,
    f.net_sales_amount AS fact_net_sales,

    i.estimated_cogs AS intermediate_cogs,
    f.estimated_cogs AS fact_cogs,

    i.estimated_gross_profit AS intermediate_gross_profit,
    f.estimated_gross_profit AS fact_gross_profit

FROM intermediate AS i
CROSS JOIN fact AS f

WHERE
       i.total_rows
            IS DISTINCT FROM f.total_rows

    OR i.total_quantity
            IS DISTINCT FROM f.total_quantity

    OR i.gross_sales_amount
            IS DISTINCT FROM f.gross_sales_amount

    OR i.discount_amount
            IS DISTINCT FROM f.discount_amount

    OR i.net_sales_amount
            IS DISTINCT FROM f.net_sales_amount

    OR i.estimated_cogs
            IS DISTINCT FROM f.estimated_cogs

    OR i.estimated_gross_profit
            IS DISTINCT FROM f.estimated_gross_profit