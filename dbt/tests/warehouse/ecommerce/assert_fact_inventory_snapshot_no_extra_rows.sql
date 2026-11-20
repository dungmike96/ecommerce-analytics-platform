-- ============================================================
-- RECONCILIATION TEST
--
-- fact_inventory_snapshot
--          ↓
-- stg_nhanh_inventory
--
-- Contract:
-- Warehouse must not contain inventory grains
-- that do not exist in staging.
--
-- Expected:
-- 0 rows
-- ============================================================

WITH staging AS (

    SELECT
        snapshot_date,
        product_id,
        depot_id

    FROM {{ ref('stg_nhanh_inventory') }}

),

warehouse AS (

    SELECT
        snapshot_date,
        product_id,
        depot_id

    FROM {{ ref('fact_inventory_snapshot') }}

),

extra_warehouse_rows AS (

    SELECT
        w.snapshot_date,
        w.product_id,
        w.depot_id

    FROM warehouse AS w

    LEFT JOIN staging AS s
        ON  w.snapshot_date = s.snapshot_date
        AND w.product_id    = s.product_id
        AND w.depot_id      = s.depot_id

    WHERE s.product_id IS NULL

)

SELECT *
FROM extra_warehouse_rows