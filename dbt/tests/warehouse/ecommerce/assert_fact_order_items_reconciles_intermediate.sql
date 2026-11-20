-- ============================================================
-- Reconciliation:
-- int_nhanh_order_items_enriched -> fact_order_items
--
-- Test fails if:
--   - item missing from either side
--   - quantity changes
--   - financial metrics change
--
-- Expected result: 0 rows
-- ============================================================

WITH intermediate AS (

    SELECT
        order_product_id,
        order_id,
        product_id,
        quantity,
        gross_sales_amount,
        discount_amount,
        net_sales_amount,
        estimated_cogs,
        estimated_gross_profit

    FROM {{ ref('int_nhanh_order_items_enriched') }}

),

fact AS (

    SELECT
        order_product_id,
        order_id,
        product_id,
        quantity,
        gross_sales_amount,
        discount_amount,
        net_sales_amount,
        estimated_cogs,
        estimated_gross_profit

    FROM {{ ref('fact_order_items') }}

)

SELECT
    COALESCE(i.order_product_id, f.order_product_id)
        AS order_product_id,

    i.order_id AS intermediate_order_id,
    f.order_id AS fact_order_id,

    i.quantity AS intermediate_quantity,
    f.quantity AS fact_quantity,

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

FULL OUTER JOIN fact AS f
    ON i.order_product_id = f.order_product_id

WHERE
       i.order_product_id IS NULL
    OR f.order_product_id IS NULL

    OR i.order_id IS DISTINCT FROM f.order_id
    OR i.product_id IS DISTINCT FROM f.product_id
    OR i.quantity IS DISTINCT FROM f.quantity

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