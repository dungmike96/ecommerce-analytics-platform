-- ============================================================
-- WAREHOUSE DIMENSION
-- Calendar Date
--
-- Grain:
--   1 row = 1 calendar date
--
-- Purpose:
--   Shared calendar dimension for BI time analysis.
-- ============================================================

WITH date_bounds AS (

    SELECT

        MIN(order_date) AS min_date,

        -- Extend calendar through the end of the latest year
        -- available in the order dataset.
        (
            DATE_TRUNC(
                'year',
                MAX(order_date)
            )
            + INTERVAL '1 year'
            - INTERVAL '1 day'
        )::date AS max_date

    FROM {{ ref('int_nhanh_orders_classified') }}

),

date_spine AS (

    SELECT
        GENERATE_SERIES(
            min_date::timestamp,
            max_date::timestamp,
            INTERVAL '1 day'
        )::date AS full_date

    FROM date_bounds

),

final AS (

    SELECT

        -- Example:
        -- 2026-09-28 -> 20260928
        TO_CHAR(full_date, 'YYYYMMDD')::integer
            AS date_key,

        full_date,

        EXTRACT(YEAR FROM full_date)::integer
            AS year,

        EXTRACT(QUARTER FROM full_date)::integer
            AS quarter,

        EXTRACT(MONTH FROM full_date)::integer
            AS month_number,

        TO_CHAR(full_date, 'FMMonth')
            AS month_name,

        TO_CHAR(full_date, 'YYYY-MM')
            AS year_month,

        EXTRACT(DAY FROM full_date)::integer
            AS day_of_month,

        EXTRACT(DOW FROM full_date)::integer
            AS day_of_week,

        TO_CHAR(full_date, 'FMDay')
            AS day_name,

        CASE
            WHEN EXTRACT(DOW FROM full_date) IN (0, 6)
                THEN TRUE
            ELSE FALSE
        END AS is_weekend

    FROM date_spine

)

SELECT *
FROM final