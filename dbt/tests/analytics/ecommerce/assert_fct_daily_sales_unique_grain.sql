-- ============================================================
-- 15.2.7.5
-- Singular test: fct_daily_sales grain
--
-- Expected grain:
--   1 row = 1 order_date x 1 sale_channel_id
--
-- PASS condition:
--   Query returns 0 rows
-- ============================================================

SELECT
    order_date,
    sale_channel_id,
    COUNT(*) AS row_count

FROM {{ ref('fct_daily_sales') }}

GROUP BY
    order_date,
    sale_channel_id

HAVING COUNT(*) > 1