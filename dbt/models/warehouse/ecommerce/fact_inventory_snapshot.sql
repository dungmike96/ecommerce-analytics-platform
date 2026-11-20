-- ============================================================
-- WAREHOUSE FACT:
-- fact_inventory_snapshot
--
-- Grain:
--   1 row = 1 snapshot_date x product_id x depot_id
--
-- Source:
--   stg_nhanh_inventory
--
-- Dimension:
--   dim_product
--
-- Purpose:
--   Historical daily inventory snapshot by product and depot.
--
-- Important:
--   - Negative inventory is preserved.
--   - Do NOT aggregate product_total_* across depots.
--   - Depot-level quantities are the primary fact measures.
-- ============================================================

WITH inventory AS (

    SELECT
        snapshot_date,
        snapshot_at,

        product_id,
        depot_id,

        remain_quantity,
        shipping_quantity,
        damaged_quantity,
        holding_quantity,
        transferring_quantity,
        available_quantity,

        warranty_remain_quantity,
        warranty_holding_quantity,

        product_total_remain_quantity,
        product_total_available_quantity,

        has_negative_remain

    FROM {{ ref('stg_nhanh_inventory') }}

),

final AS (

    SELECT

        -- ====================================================
        -- FACT GRAIN
        -- ====================================================

        snapshot_date,

        TO_CHAR(snapshot_date, 'YYYYMMDD')::integer
            AS snapshot_date_key,

        product_id,
        depot_id,


        -- ====================================================
        -- DEPOT INVENTORY MEASURES
        -- ====================================================

        remain_quantity,

        shipping_quantity,

        damaged_quantity,

        holding_quantity,

        transferring_quantity,

        available_quantity,


        -- ====================================================
        -- WARRANTY INVENTORY
        -- ====================================================

        warranty_remain_quantity,

        warranty_holding_quantity,


        -- ====================================================
        -- PRODUCT-LEVEL RECONCILIATION
        --
        -- These values may repeat across depots.
        -- Do NOT SUM across depot rows.
        -- ====================================================

        product_total_remain_quantity,

        product_total_available_quantity,


        -- ====================================================
        -- QUALITY FLAG
        -- ====================================================

        has_negative_remain,


        -- ====================================================
        -- SNAPSHOT METADATA
        -- ====================================================

        snapshot_at

    FROM inventory

)

SELECT *
FROM final