-- ============================================================
-- RAW.NHANH_ORDERS - DATA QUALITY CHECKS
-- ============================================================
-- ------------------------------------------------------------
-- 1. Tổng quan RAW
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS total_orders,
    COUNT(DISTINCT order_id) AS unique_orders,
    COUNT(DISTINCT source_depot_id) AS total_depots,
    MIN(source_created_at) AS oldest_order,
    MAX(source_created_at) AS newest_order,
    MAX(source_updated_at) AS latest_updated
FROM raw.nhanh_orders;


-- ------------------------------------------------------------
-- 2. Kiểm tra duplicate order_id
-- Kết quả mong đợi: 0 rows
-- ------------------------------------------------------------

SELECT
    order_id,
    COUNT(*) AS duplicate_count
FROM raw.nhanh_orders
GROUP BY order_id
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC;


-- ------------------------------------------------------------
-- 3. Kiểm tra dữ liệu bắt buộc bị thiếu
-- ------------------------------------------------------------

SELECT
    COUNT(*) FILTER (WHERE order_id IS NULL) AS missing_order_id,
    COUNT(*) FILTER (WHERE api_response IS NULL) AS missing_payload,
    COUNT(*) FILTER (WHERE source_created_at IS NULL) AS missing_created_at,
    COUNT(*) FILTER (WHERE source_updated_at IS NULL) AS missing_updated_at
FROM raw.nhanh_orders;


-- ------------------------------------------------------------
-- 4. Phân bố đơn hàng theo năm
-- ------------------------------------------------------------

SELECT
    EXTRACT(YEAR FROM source_created_at)::int AS year,
    COUNT(*) AS total_orders
FROM raw.nhanh_orders
GROUP BY 1
ORDER BY 1;


-- ------------------------------------------------------------
-- 5. Phân bố theo depot
-- ------------------------------------------------------------

SELECT
    source_depot_id,
    COUNT(*) AS total_orders
FROM raw.nhanh_orders
GROUP BY source_depot_id
ORDER BY total_orders DESC;


-- ------------------------------------------------------------
-- 6. 10 records được ingestion gần nhất
-- ------------------------------------------------------------

SELECT
    order_id,
    source_depot_id,
    source_created_at,
    source_updated_at,
    first_ingested_at,
    last_ingested_at
FROM raw.nhanh_orders
ORDER BY last_ingested_at DESC
LIMIT 10;


-- ------------------------------------------------------------
-- 7. Watermark
-- ------------------------------------------------------------

SELECT *
FROM raw.ingestion_watermark;