-- ============================================================
-- WAREHOUSE DIMENSION
-- Order Status
--
-- Grain:
--   1 row = 1 status_id
--
-- Source of mapping:
--   Official Nhanh.vn API documentation
-- ============================================================

WITH statuses AS (

    SELECT DISTINCT
        status_id

    FROM {{ ref('int_nhanh_orders_classified') }}

    WHERE status_id IS NOT NULL

),

final AS (

    SELECT
        status_id,

        -- Official Nhanh.vn status mapping
        CASE status_id
            WHEN 40 THEN 'Đã đóng gói'
            WHEN 42 THEN 'Đang đóng gói'
            WHEN 43 THEN 'Chờ thu gom'
            WHEN 54 THEN 'Đơn mới'
            WHEN 55 THEN 'Đang xác nhận'
            WHEN 56 THEN 'Đã xác nhận'
            WHEN 57 THEN 'Chờ khách xác nhận'
            WHEN 58 THEN 'Hãng vận chuyển hủy đơn'
            WHEN 59 THEN 'Đang chuyển'
            WHEN 60 THEN 'Thành công'
            WHEN 61 THEN 'Thất bại'
            WHEN 63 THEN 'Khách hủy'
            WHEN 64 THEN 'Hệ thống hủy'
            WHEN 68 THEN 'Hết hàng'
            WHEN 71 THEN 'Đang chuyển hoàn'
            WHEN 72 THEN 'Đã chuyển hoàn'
            WHEN 73 THEN 'Đổi kho xuất hàng'
            WHEN 74 THEN 'Xác nhận hoàn'
            ELSE 'UNKNOWN'
        END AS status_name,

        CASE
            WHEN status_id IN (
                40, 42, 43,
                54, 55, 56, 57, 58,
                59, 60, 61, 63, 64,
                68, 71, 72, 73, 74
            )
            THEN 'VERIFIED'
            ELSE 'UNVERIFIED'
        END AS status_mapping_state,

        CASE
            WHEN status_id IN (
                40, 42, 43,
                54, 55, 56, 57, 58,
                59, 60, 61, 63, 64,
                68, 71, 72, 73, 74
            )
            THEN TRUE
            ELSE FALSE
        END AS is_verified

    FROM statuses

)

SELECT *
FROM final