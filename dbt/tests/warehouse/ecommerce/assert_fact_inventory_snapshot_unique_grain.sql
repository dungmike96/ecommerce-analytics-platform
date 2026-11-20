-- ============================================================
-- GRAIN CONTRACT TEST
-- fact_inventory_snapshot
--
-- Expected grain:
--   1 row =
--   snapshot_date
--   x product_id
--   x depot_id
--
-- Test fails when duplicate grain exists.
-- Expected result:
--   0 rows
-- ============================================================

SELECT
    snapshot_date,
    product_id,
    depot_id,
    COUNT(*) AS row_count

FROM {{ ref('fact_inventory_snapshot') }}

GROUP BY
    snapshot_date,
    product_id,
    depot_id

HAVING COUNT(*) > 1