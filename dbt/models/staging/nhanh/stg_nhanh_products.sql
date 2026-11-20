-- ============================================================
-- STAGING: NHANH.VN PRODUCTS
--
-- Grain:
--   1 row = 1 product_id
--
-- Source:
--   raw.nhanh_products
--
-- Purpose:
--   Parse and standardize product master data from Nhanh.vn.
--
-- Important:
--   Inventory is intentionally NOT modeled here.
--   Inventory history belongs to stg_nhanh_inventory.
-- ============================================================

WITH source AS (

    SELECT
        product_id,
        api_response,
        source_created_at,
        source_updated_at,
        first_ingested_at,
        last_ingested_at

    FROM {{ source('nhanh', 'nhanh_products') }}

),

extracted AS (

    SELECT

        -- ====================================================
        -- PRODUCT KEY
        -- ====================================================

        product_id::bigint
            AS product_id,


        -- ====================================================
        -- PRODUCT HIERARCHY
        -- ====================================================

        NULLIF(
            api_response ->> 'parentId',
            ''
        )::bigint
            AS parent_product_id,

        NULLIF(
            BTRIM(api_response ->> 'code'),
            ''
        )
            AS product_code,

        NULLIF(
            BTRIM(api_response ->> 'barcode'),
            ''
        )
            AS barcode,

        NULLIF(
            BTRIM(api_response ->> 'name'),
            ''
        )
            AS product_name,

        NULLIF(
            BTRIM(api_response ->> 'otherName'),
            ''
        )
            AS other_name,


        -- ====================================================
        -- PRODUCT STATUS / TYPE
        -- ====================================================

        NULLIF(
            api_response ->> 'status',
            ''
        )::integer
            AS status_id,

        NULLIF(
            api_response ->> 'type',
            ''
        )::integer
            AS product_type_id,


        -- ====================================================
        -- CATEGORY / BRAND
        -- ====================================================

        NULLIF(
            api_response ->> 'categoryId',
            ''
        )::bigint
            AS category_id,

        NULLIF(
            api_response ->> 'internalCategoryId',
            ''
        )::bigint
            AS internal_category_id,

        NULLIF(
            api_response ->> 'brandId',
            ''
        )::bigint
            AS brand_id,


        -- ====================================================
        -- PRICE
        -- ====================================================

        NULLIF(
            api_response -> 'prices' ->> 'retail',
            ''
        )::numeric
            AS retail_price,

        NULLIF(
            api_response -> 'prices' ->> 'retailVat',
            ''
        )::numeric
            AS retail_vat_amount,

        NULLIF(
            api_response -> 'prices' ->> 'import',
            ''
        )::numeric
            AS import_price,

        NULLIF(
            api_response -> 'prices' ->> 'importVat',
            ''
        )::numeric
            AS import_vat_amount,

        NULLIF(
            api_response -> 'prices' ->> 'old',
            ''
        )::numeric
            AS old_price,

        NULLIF(
            api_response -> 'prices' ->> 'wholesale',
            ''
        )::numeric
            AS wholesale_price,

        NULLIF(
            api_response -> 'prices' ->> 'avgCost',
            ''
        )::numeric
            AS average_cost,


        -- ====================================================
        -- VAT MODE
        -- ====================================================

        NULLIF(
            api_response ->> 'priceVatMode',
            ''
        )::integer
            AS price_vat_mode,

        NULLIF(
            api_response ->> 'importPriceVatMode',
            ''
        )::integer
            AS import_price_vat_mode,


        -- ====================================================
        -- SHIPPING ATTRIBUTES
        -- ====================================================

        NULLIF(
            api_response -> 'shipping' ->> 'width',
            ''
        )::numeric
            AS width,

        NULLIF(
            api_response -> 'shipping' ->> 'height',
            ''
        )::numeric
            AS height,

        NULLIF(
            api_response -> 'shipping' ->> 'length',
            ''
        )::numeric
            AS length,

        NULLIF(
            api_response -> 'shipping' ->> 'weight',
            ''
        )::numeric
            AS weight,


        -- ====================================================
        -- OTHER PRODUCT ATTRIBUTES
        -- ====================================================

        NULLIF(
            BTRIM(api_response ->> 'countryName'),
            ''
        )
            AS country_name,

        NULLIF(
            BTRIM(api_response -> 'units' ->> 'name'),
            ''
        )
            AS unit_name,

        NULLIF(
            BTRIM(api_response -> 'images' ->> 'avatar'),
            ''
        )
            AS avatar_url,


        -- ====================================================
        -- SOURCE TIMESTAMPS
        -- Already converted by ingestion
        -- ====================================================

        source_created_at,
        source_updated_at,


        -- ====================================================
        -- INGESTION METADATA
        -- ====================================================

        first_ingested_at,
        last_ingested_at

    FROM source

)

SELECT *
FROM extracted