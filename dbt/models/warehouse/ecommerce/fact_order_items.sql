-- ============================================================
-- WAREHOUSE FACT: fact_order_items
--
-- Grain:
--   1 row = 1 order_product_id
--
-- Source:
--   intermediate.int_nhanh_order_items_enriched
--
-- Business / financial calculations are performed upstream
-- in the Intermediate layer.
-- ============================================================

WITH order_items AS (

    SELECT *
    FROM {{ ref('int_nhanh_order_items_enriched') }}

),

final AS (

    SELECT

        -- ====================================================
        -- KEYS
        -- ====================================================

        order_product_id,
        order_id,
        product_id,


        -- ====================================================
        -- PRODUCT ATTRIBUTES
        -- ====================================================

        product_code,
        product_name,


        -- ====================================================
        -- QUANTITY
        -- ====================================================

        quantity,


        -- ====================================================
        -- FINANCIAL MEASURES
        -- ====================================================

        unit_price,
        discount_amount,
        avg_cost,
        total_amount,

        gross_sales_amount,
        net_sales_amount,
        estimated_cogs,
        estimated_gross_profit,


        -- ====================================================
        -- DATA QUALITY FLAGS
        -- ====================================================

        has_cost,
        matches_expected_net_formula

    FROM order_items

)

SELECT *
FROM final