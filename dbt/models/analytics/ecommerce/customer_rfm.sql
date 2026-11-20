
{{ config(materialized='table') }}

-- ============================================================
-- ZOSEO RFM ANALYTICS
-- Grain: 1 row = 1 customer_id
-- Source: customer_lifetime_value
--
-- R = Recency (5: recent, 1: oldest)
-- F = Frequency (5: most orders)
-- M = Monetary (5: highest historical revenue)
--
-- This model does not modify CLV or Priority rules.
-- ============================================================

WITH source_data AS (

    SELECT
        customer_id,
        total_orders,
        first_order_date,
        last_order_date,
        lifetime_revenue,
        avg_order_value,
        repeat_customer_flag,
        customer_segment,
        priority_member_flag,

        GREATEST(
            CURRENT_DATE - last_order_date::date,
            0
        ) AS recency_days

    FROM {{ ref('customer_lifetime_value') }}

),

-- Calculate ranks by distinct values to avoid
-- assigning different scores to identical values.
distinct_r AS (

    SELECT
        recency_days,
        DENSE_RANK() OVER (
            ORDER BY recency_days DESC
        ) AS rank_value,
        COUNT(*) OVER () AS distinct_count
    FROM (
        SELECT DISTINCT recency_days
        FROM source_data
    ) d

),

distinct_f AS (

    SELECT
        total_orders,
        DENSE_RANK() OVER (
            ORDER BY total_orders ASC
        ) AS rank_value,
        COUNT(*) OVER () AS distinct_count
    FROM (
        SELECT DISTINCT total_orders
        FROM source_data
    ) d

),

distinct_m AS (

    SELECT
        lifetime_revenue,
        DENSE_RANK() OVER (
            ORDER BY lifetime_revenue ASC
        ) AS rank_value,
        COUNT(*) OVER () AS distinct_count
    FROM (
        SELECT DISTINCT lifetime_revenue
        FROM source_data
    ) d

),

scored AS (

    SELECT
        s.*,

        1 + FLOOR(
            4.0 * (r.rank_value - 1)
            / GREATEST(r.distinct_count - 1, 1)
        )::integer AS r_score,

        1 + FLOOR(
            4.0 * (f.rank_value - 1)
            / GREATEST(f.distinct_count - 1, 1)
        )::integer AS f_score,

        1 + FLOOR(
            4.0 * (m.rank_value - 1)
            / GREATEST(m.distinct_count - 1, 1)
        )::integer AS m_score

    FROM source_data s

    JOIN distinct_r r
        ON s.recency_days = r.recency_days

    JOIN distinct_f f
        ON s.total_orders = f.total_orders

    JOIN distinct_m m
        ON s.lifetime_revenue = m.lifetime_revenue

),

final AS (

    SELECT
        customer_id,
        total_orders,
        first_order_date,
        last_order_date,
        lifetime_revenue,
        avg_order_value,
        recency_days,

        repeat_customer_flag,
        customer_segment,
        priority_member_flag,

        r_score,
        f_score,
        m_score,

        (
            r_score::text ||
            f_score::text ||
            m_score::text
        ) AS rfm_code,

        (r_score + f_score + m_score)
            AS rfm_total_score,

        CASE
            WHEN r_score >= 4
             AND f_score >= 4
             AND m_score >= 4
                THEN 'Champions'

            WHEN r_score >= 3
             AND f_score >= 4
                THEN 'Loyal Customers'

            WHEN r_score >= 4
             AND total_orders = 1
                THEN 'New Customers'

            WHEN r_score <= 2
             AND f_score >= 4
                THEN 'At Risk'

            WHEN r_score <= 2
             AND m_score >= 4
                THEN 'High Value Lost'

            WHEN r_score >= 3
             AND f_score <= 3
                THEN 'Potential Loyalists'

            ELSE 'Regular'
        END AS rfm_segment,

        CURRENT_TIMESTAMP AS calculated_at

    FROM scored

)

SELECT *
FROM final
