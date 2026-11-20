-- ============================================================
-- WAREHOUSE DIMENSION
-- Time
--
-- Grain:
--   1 row = 1 hour of day
--
-- Purpose:
--   Analyze ecommerce behavior by hour / time slot
-- ============================================================

WITH hours AS (

    SELECT
        generate_series(0, 23) AS hour_of_day

),

final AS (

    SELECT

        -- ====================================================
        -- KEY
        -- ====================================================

        hour_of_day AS time_key,


        -- ====================================================
        -- HOUR
        -- ====================================================

        hour_of_day,
        LPAD(hour_of_day::text, 2, '0') || ':00'
            AS hour_label,


        -- ====================================================
        -- TIME SLOT
        -- ====================================================

        CASE
            WHEN hour_of_day BETWEEN 0 AND 5
                THEN '00:00-05:59 Late Night'

            WHEN hour_of_day BETWEEN 6 AND 8
                THEN '06:00-08:59 Morning'

            WHEN hour_of_day BETWEEN 9 AND 11
                THEN '09:00-11:59 Morning Shopping'

            WHEN hour_of_day BETWEEN 12 AND 13
                THEN '12:00-13:59 Lunch Break'

            WHEN hour_of_day BETWEEN 14 AND 17
                THEN '14:00-17:59 Afternoon'

            WHEN hour_of_day BETWEEN 18 AND 20
                THEN '18:00-20:59 Evening Prime'

            ELSE '21:00-23:59 Night Prime'
        END AS time_slot,


        -- ====================================================
        -- SORT
        -- ====================================================

        CASE
            WHEN hour_of_day BETWEEN 0 AND 5 THEN 1
            WHEN hour_of_day BETWEEN 6 AND 8 THEN 2
            WHEN hour_of_day BETWEEN 9 AND 11 THEN 3
            WHEN hour_of_day BETWEEN 12 AND 13 THEN 4
            WHEN hour_of_day BETWEEN 14 AND 17 THEN 5
            WHEN hour_of_day BETWEEN 18 AND 20 THEN 6
            ELSE 7
        END AS time_slot_sort,


        -- ====================================================
        -- DAY PART
        -- ====================================================

        CASE
            WHEN hour_of_day BETWEEN 0 AND 5 THEN 'Night'
            WHEN hour_of_day BETWEEN 6 AND 11 THEN 'Morning'
            WHEN hour_of_day BETWEEN 12 AND 17 THEN 'Afternoon'
            ELSE 'Evening'
        END AS day_part

    FROM hours

)

SELECT *
FROM final
ORDER BY hour_of_day