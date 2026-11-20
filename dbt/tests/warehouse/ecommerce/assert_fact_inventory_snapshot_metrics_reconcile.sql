-- ============================================================
-- METRIC RECONCILIATION TEST
--
-- Validate inventory measures between Staging and Warehouse.
--
-- Expected:
-- 0 rows
-- ============================================================

WITH staging AS (

    SELECT
        snapshot_date,
        product_id,
        depot_id,

        remain_quantity,
        available_quantity,
        shipping_quantity,
        damaged_quantity,
        holding_quantity,
        transferring_quantity

    FROM {{ ref('stg_nhanh_inventory') }}

),

warehouse AS (

    SELECT
        snapshot_date,
        product_id,
        depot_id,

        remain_quantity,
        available_quantity,
        shipping_quantity,
        damaged_quantity,
        holding_quantity,
        transferring_quantity

    FROM {{ ref('fact_inventory_snapshot') }}

)

SELECT
    s.snapshot_date,
    s.product_id,
    s.depot_id,

    s.remain_quantity
        AS staging_remain,

    w.remain_quantity
        AS warehouse_remain,

    s.available_quantity
        AS staging_available,

    w.available_quantity
        AS warehouse_available

FROM staging AS s

INNER JOIN warehouse AS w
    ON  s.snapshot_date = w.snapshot_date
    AND s.product_id    = w.product_id
    AND s.depot_id      = w.depot_id

WHERE
       s.remain_quantity
           IS DISTINCT FROM w.remain_quantity

    OR s.available_quantity
           IS DISTINCT FROM w.available_quantity

    OR s.shipping_quantity
           IS DISTINCT FROM w.shipping_quantity

    OR s.damaged_quantity
           IS DISTINCT FROM w.damaged_quantity

    OR s.holding_quantity
           IS DISTINCT FROM w.holding_quantity

    OR s.transferring_quantity
           IS DISTINCT FROM w.transferring_quantity