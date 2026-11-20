-- ============================================================
-- WAREHOUSE DIMENSION
-- Sales Channel
--
-- Grain:
--   1 row = 1 sale_channel_id
--
-- Source of mapping:
--   Official Nhanh.vn API documentation
--
-- Important:
--   sale_channel_name is the official Nhanh.vn definition.
--   sale_channel_group is an internal DWH classification.
-- ============================================================

WITH channels AS (

    SELECT DISTINCT
        sale_channel_id

    FROM {{ ref('int_nhanh_orders_classified') }}

    WHERE sale_channel_id IS NOT NULL

),

final AS (

    SELECT
        sale_channel_id,

        -- Official Nhanh.vn sale channel mapping
        CASE sale_channel_id
            WHEN 1  THEN 'Admin'
            WHEN 2  THEN 'Website'
            WHEN 10 THEN 'API'
            WHEN 20 THEN 'Facebook'
            WHEN 21 THEN 'Instagram'
            WHEN 41 THEN 'Lazada'
            WHEN 42 THEN 'Shopee'
            WHEN 43 THEN 'Sendo'
            WHEN 45 THEN 'Tiki'
            WHEN 48 THEN 'TikTok Shop'
            WHEN 49 THEN 'Zalo OA'
            WHEN 50 THEN 'Shopee Chat'
            WHEN 51 THEN 'Lazada Chat'
            WHEN 52 THEN 'Zalo Personal'
            ELSE 'UNKNOWN'
        END AS sale_channel_name,

        -- Internal DWH classification
        CASE
            WHEN sale_channel_id IN (41, 42, 43, 45, 48)
                THEN 'MARKETPLACE'

            WHEN sale_channel_id = 2
                THEN 'OWNED_ONLINE'

            WHEN sale_channel_id IN (20, 21, 49, 50, 51, 52)
                THEN 'SOCIAL'

            WHEN sale_channel_id = 10
                THEN 'API'

            WHEN sale_channel_id = 1
                THEN 'MANUAL'

            ELSE 'UNKNOWN'
        END AS sale_channel_group,

        CASE
            WHEN sale_channel_id IN (
                1, 2, 10, 20, 21,
                41, 42, 43, 45, 48,
                49, 50, 51, 52
            )
            THEN TRUE
            ELSE FALSE
        END AS is_verified

    FROM channels

)

SELECT *
FROM final