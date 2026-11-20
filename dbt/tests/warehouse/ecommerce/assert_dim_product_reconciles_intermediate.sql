-- ============================================================
-- RECONCILIATION TEST:
-- int_nhanh_order_items_enriched
--              ↓
--         dim_product
--
-- Business rule:
--
-- Every historical product referenced by order items
-- MUST exist in dim_product.
--
-- dim_product MAY contain additional products because the
-- canonical product master now comes from Nhanh.vn Product API.
--
-- Product name differences are NOT considered failures because
-- the current Product API name may differ from historical
-- transactional product names.
--
-- Expected result:
--   0 rows
-- ============================================================

WITH intermediate_products AS (

    SELECT DISTINCT
        product_id

    FROM {{ ref('int_nhanh_order_items_enriched') }}

    WHERE product_id IS NOT NULL

),

dimension_products AS (

    SELECT
        product_id

    FROM {{ ref('dim_product') }}

),

missing_from_dimension AS (

    SELECT
        i.product_id

    FROM intermediate_products AS i

    LEFT JOIN dimension_products AS d
        ON i.product_id = d.product_id

    WHERE d.product_id IS NULL

)

SELECT *
FROM missing_from_dimension