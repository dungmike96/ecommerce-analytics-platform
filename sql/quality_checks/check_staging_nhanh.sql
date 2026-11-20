-- ============================================================
-- NHANH.VN - FINAL STAGING VALIDATION
-- RAW vs STAGING reconciliation
-- ============================================================


-- ============================================================
-- 1. ORDERS: RAW vs STAGING
-- ============================================================

SELECT
    (SELECT COUNT(*)
     FROM raw.nhanh_orders) AS raw_orders,

    (SELECT COUNT(*)
     FROM staging.stg_nhanh_orders) AS staging_orders,

    (SELECT COUNT(*)
     FROM raw.nhanh_orders)
    -
    (SELECT COUNT(*)
     FROM staging.stg_nhanh_orders) AS difference;


-- ============================================================
-- 2. ORDER ITEMS: RAW JSON vs STAGING
-- ============================================================

SELECT
    (
        SELECT COUNT(*)
        FROM raw.nhanh_orders AS o
        CROSS JOIN LATERAL jsonb_array_elements(
            o.api_response -> 'products'
        ) AS p(product)
        WHERE jsonb_typeof(
            o.api_response -> 'products'
        ) = 'array'
    ) AS raw_product_lines,

    (
        SELECT COUNT(*)
        FROM staging.stg_nhanh_order_items
    ) AS staging_product_lines,

    (
        SELECT COUNT(*)
        FROM raw.nhanh_orders AS o
        CROSS JOIN LATERAL jsonb_array_elements(
            o.api_response -> 'products'
        ) AS p(product)
        WHERE jsonb_typeof(
            o.api_response -> 'products'
        ) = 'array'
    )
    -
    (
        SELECT COUNT(*)
        FROM staging.stg_nhanh_order_items
    ) AS difference;


-- ============================================================
-- 3. GIFTS: RAW JSON vs STAGING
-- ============================================================

SELECT
    (
        SELECT COUNT(*)
        FROM raw.nhanh_orders AS o
        CROSS JOIN LATERAL jsonb_array_elements(
            o.api_response -> 'gifts'
        ) AS g(gift)
        WHERE jsonb_typeof(
            o.api_response -> 'gifts'
        ) = 'array'
    ) AS raw_gift_lines,

    (
        SELECT COUNT(*)
        FROM staging.stg_nhanh_order_gifts
    ) AS staging_gift_lines,

    (
        SELECT COUNT(*)
        FROM raw.nhanh_orders AS o
        CROSS JOIN LATERAL jsonb_array_elements(
            o.api_response -> 'gifts'
        ) AS g(gift)
        WHERE jsonb_typeof(
            o.api_response -> 'gifts'
        ) = 'array'
    )
    -
    (
        SELECT COUNT(*)
        FROM staging.stg_nhanh_order_gifts
    ) AS difference;


-- ============================================================
-- 4. FINAL GRAIN CHECK
-- ============================================================

SELECT
    'orders' AS model,
    COUNT(*) AS total_rows,
    COUNT(DISTINCT order_id) AS unique_rows,
    COUNT(*) - COUNT(DISTINCT order_id) AS duplicates
FROM staging.stg_nhanh_orders

UNION ALL

SELECT
    'order_items',
    COUNT(*),
    COUNT(DISTINCT order_product_id),
    COUNT(*) - COUNT(DISTINCT order_product_id)
FROM staging.stg_nhanh_order_items

UNION ALL

SELECT
    'order_gifts',
    COUNT(*),
    COUNT(DISTINCT (order_id, gift_line_number)),
    COUNT(*) - COUNT(DISTINCT (order_id, gift_line_number))
FROM staging.stg_nhanh_order_gifts;