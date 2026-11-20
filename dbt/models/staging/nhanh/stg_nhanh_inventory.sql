-- ============================================================
-- STAGING: NHANH.VN INVENTORY SNAPSHOT
--
-- Grain:
--   1 row = 1 snapshot_date x product_id x depot_id
--
-- Source:
--   raw.nhanh_inventory_snapshots
--
-- Purpose:
--   Standardize depot-level inventory snapshot metrics.
--
-- Important:
--   Negative inventory values are preserved.
--   Do NOT force negative quantities to zero.
-- ============================================================

WITH source AS (

    SELECT
        snapshot_date,
        product_id,
        depot_id,
        api_response,
        snapshot_at

    FROM {{ source('nhanh', 'nhanh_inventory_snapshots') }}

),

extracted AS (

    SELECT

        -- ====================================================
        -- SNAPSHOT KEY
        -- ====================================================

        snapshot_date::date
            AS snapshot_date,

        product_id::bigint
            AS product_id,

        depot_id::bigint
            AS depot_id,


        -- ====================================================
        -- DEPOT INVENTORY
        -- ====================================================

        NULLIF(
            api_response
                -> 'inventory'
                -> 'depot'
                ->> 'remain',
            ''
        )::numeric
            AS remain_quantity,

        NULLIF(
            api_response
                -> 'inventory'
                -> 'depot'
                ->> 'shipping',
            ''
        )::numeric
            AS shipping_quantity,

        NULLIF(
            api_response
                -> 'inventory'
                -> 'depot'
                ->> 'damaged',
            ''
        )::numeric
            AS damaged_quantity,

        NULLIF(
            api_response
                -> 'inventory'
                -> 'depot'
                ->> 'holding',
            ''
        )::numeric
            AS holding_quantity,

        NULLIF(
            api_response
                -> 'inventory'
                -> 'depot'
                ->> 'transfering',
            ''
        )::numeric
            AS transferring_quantity,

        NULLIF(
            api_response
                -> 'inventory'
                -> 'depot'
                ->> 'available',
            ''
        )::numeric
            AS available_quantity,


        -- ====================================================
        -- WARRANTY INVENTORY
        -- ====================================================

        NULLIF(
            api_response
                -> 'inventory'
                -> 'depot'
                -> 'warranty'
                ->> 'remain',
            ''
        )::numeric
            AS warranty_remain_quantity,

        NULLIF(
            api_response
                -> 'inventory'
                -> 'depot'
                -> 'warranty'
                ->> 'holding',
            ''
        )::numeric
            AS warranty_holding_quantity,


        -- ====================================================
        -- PRODUCT TOTAL INVENTORY
        --
        -- Useful for reconciliation with Nhanh API.
        -- Do NOT SUM these values across depot rows because
        -- productTotal is repeated for each depot row.
        -- ====================================================

        NULLIF(
            api_response
                -> 'inventory'
                -> 'productTotal'
                ->> 'remain',
            ''
        )::numeric
            AS product_total_remain_quantity,

        NULLIF(
            api_response
                -> 'inventory'
                -> 'productTotal'
                ->> 'available',
            ''
        )::numeric
            AS product_total_available_quantity,


        -- ====================================================
        -- DATA QUALITY FLAGS
        -- ====================================================

        (
            COALESCE(
                NULLIF(
                    api_response
                        -> 'inventory'
                        -> 'depot'
                        ->> 'remain',
                    ''
                )::numeric,
                0
            ) < 0
        )
            AS has_negative_remain,


        -- ====================================================
        -- SNAPSHOT METADATA
        -- ====================================================

        snapshot_at

    FROM source

)

SELECT *
FROM extracted