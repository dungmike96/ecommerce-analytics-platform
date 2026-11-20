-- ============================================================
-- DIMENSION: dim_product
--
-- Grain:
--   1 row = 1 product_id
--
-- Sources:
--   1. stg_nhanh_products
--      -> Current canonical product master from Nhanh.vn API
--
--   2. int_nhanh_order_items_enriched
--      -> Historical fallback for products that appeared in
--         orders but are no longer returned by Product API
--
-- Strategy:
--   Product API has priority.
--   Historical order products are added ONLY when the product
--   does not exist in the current Product API.
--
-- Purpose:
--   Preserve referential integrity for historical facts while
--   using Product API as the canonical current product master.
-- ============================================================


WITH product_master AS (

    SELECT

        product_id,

        parent_product_id,

        product_code,
        barcode,

        product_name,
        other_name,

        status_id,
        product_type_id,

        category_id,
        internal_category_id,
        brand_id,

        retail_price,
        wholesale_price,
        import_price,
        average_cost,

        price_vat_mode,
        import_price_vat_mode,

        width,
        height,
        length,
        weight,

        country_name,
        unit_name,
        avatar_url,

        source_created_at,
        source_updated_at,

        first_ingested_at,
        last_ingested_at,

        'product_api'::text
            AS product_source

    FROM {{ ref('stg_nhanh_products') }}

),


-- ============================================================
-- Historical products observed in order items
--
-- One row per product_id.
-- MAX(product_name) is safe based on previous discovery:
-- each product_id maps to one product_name.
-- ============================================================

historical_order_products AS (

    SELECT

        product_id,

        MAX(product_name)
            AS product_name

    FROM {{ ref('int_nhanh_order_items_enriched') }}

    WHERE product_id IS NOT NULL

    GROUP BY product_id

),


-- ============================================================
-- Historical products missing from current Product API
-- ============================================================

historical_only AS (

    SELECT

        h.product_id,

        NULL::bigint
            AS parent_product_id,

        NULL::text
            AS product_code,

        NULL::text
            AS barcode,

        h.product_name,

        NULL::text
            AS other_name,

        NULL::integer
            AS status_id,

        NULL::integer
            AS product_type_id,

        NULL::bigint
            AS category_id,

        NULL::bigint
            AS internal_category_id,

        NULL::bigint
            AS brand_id,

        NULL::numeric
            AS retail_price,

        NULL::numeric
            AS wholesale_price,

        NULL::numeric
            AS import_price,

        NULL::numeric
            AS average_cost,

        NULL::integer
            AS price_vat_mode,

        NULL::integer
            AS import_price_vat_mode,

        NULL::numeric
            AS width,

        NULL::numeric
            AS height,

        NULL::numeric
            AS length,

        NULL::numeric
            AS weight,

        NULL::text
            AS country_name,

        NULL::text
            AS unit_name,

        NULL::text
            AS avatar_url,

        NULL::timestamptz
            AS source_created_at,

        NULL::timestamptz
            AS source_updated_at,

        NULL::timestamptz
            AS first_ingested_at,

        NULL::timestamptz
            AS last_ingested_at,

        'historical_order'::text
            AS product_source

    FROM historical_order_products h

    LEFT JOIN product_master p
        ON h.product_id = p.product_id

    WHERE p.product_id IS NULL

),


-- ============================================================
-- Final Product Dimension
-- ============================================================

final AS (

    SELECT *
    FROM product_master

    UNION ALL

    SELECT *
    FROM historical_only

)

-- ============================================================
-- Enrich Product Dimension with Category Master
--
-- LEFT JOIN:
--   Preserve products without category_id
--   Preserve historical products
--
-- Grain:
--   1 row = 1 product_id
-- ============================================================

SELECT

    p.*,

    c.category_name,
    c.category_code,
    c.parent_category_id,
    c.category_status,
    c.category_status_name

FROM final p

LEFT JOIN {{ ref('dim_product_category') }} c
    ON p.category_id = c.category_id