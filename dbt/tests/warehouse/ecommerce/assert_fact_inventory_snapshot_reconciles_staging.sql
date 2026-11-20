-- ============================================================
-- RECONCILIATION TEST
--
-- stg_nhanh_inventory
--          ↓
-- fact_inventory_snapshot
--
-- Contract:
-- Every staging inventory grain must exist exactly once
-- in the Warehouse fact.
--
-- Grain:
-- snapshot_date + product_id + depot_id
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

missing_from_warehouse AS (

    SELECT
        s.snapshot_date,
        s.product_id,
        s.depot_id

    FROM staging AS s

    LEFT JOIN warehouse AS w
        ON  s.snapshot_date = w.snapshot_date
        AND s.product_id    = w.product_id
        AND s.depot_id      = w.depot_id

    WHERE w.product_id IS NULL

)

SELECT *
FROM missing_from_warehouse