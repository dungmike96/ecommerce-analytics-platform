-- ============================================================
-- 15.5.6.2
-- Grain / coverage validation
--
-- Expected:
--   exactly 1 analytics row per status_id appearing
--   in fact_orders.
--
-- Test passes when query returns 0 rows.
-- ============================================================

WITH warehouse AS (

    SELECT
        status_id,
        COUNT(*) AS warehouse_orders

    FROM {{ ref('fact_orders') }}

    GROUP BY
        status_id

),

analytics AS (

    SELECT
        status_id,
        COUNT(*) AS analytics_rows,
        SUM(total_orders) AS analytics_orders

    FROM {{ ref('fct_status_performance') }}

    GROUP BY
        status_id

),

reconciliation AS (

    SELECT
        COALESCE(w.status_id, a.status_id)
            AS status_id,

        w.warehouse_orders,

        a.analytics_rows,
        a.analytics_orders

    FROM warehouse AS w

    FULL OUTER JOIN analytics AS a
        ON w.status_id = a.status_id

)

SELECT *
FROM reconciliation

WHERE
       warehouse_orders IS NULL
    OR analytics_rows IS NULL
    OR analytics_rows <> 1
    OR warehouse_orders IS DISTINCT FROM analytics_orders