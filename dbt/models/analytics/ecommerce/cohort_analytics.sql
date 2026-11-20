
-- ============================================================
-- ZOSEO | CUSTOMER COHORT RETENTION ANALYTICS
--
-- Grain: 1 row = 1 cohort_month + 1 month_index
--
-- Business Rules:
--   Valid orders: status_id = 60
--   Excluded channels: 42 (Shopee), 48 (TikTok)
--   Valid customers: customer_id IS NOT NULL AND <> 0
--
-- Cohort month: First valid purchase month
-- Retention rate: 0 - 100 (%)
-- ============================================================

WITH valid_orders AS (

    SELECT
        customer_id,
        order_date
    FROM {{ ref('fact_orders') }}
    WHERE status_id = 60
      AND sale_channel_id NOT IN (42, 48)
      AND customer_id IS NOT NULL
      AND customer_id <> 0
      AND order_date IS NOT NULL

),

-- 1. Identify first valid purchase per customer
first_purchase AS (

    SELECT
        customer_id,
        MIN(order_date) AS first_purchase_order,
        DATE_TRUNC('month', MIN(order_date))::date AS cohort_month
    FROM valid_orders
    GROUP BY customer_id

),

-- 2. Identify distinct active months for each customer
customer_activity AS (

    SELECT DISTINCT
        v.customer_id,
        f.cohort_month,
        DATE_TRUNC('month', v.order_date)::date AS activity_month
    FROM valid_orders AS v
    INNER JOIN first_purchase AS f
        ON v.customer_id = f.customer_id

),

-- 3. Calculate months since first purchase
customer_retention AS (

    SELECT
        customer_id,
        cohort_month,
        activity_month,

        (
            (EXTRACT(YEAR FROM activity_month)::int
             - EXTRACT(YEAR FROM cohort_month)::int) * 12
            +
            (EXTRACT(MONTH FROM activity_month)::int
             - EXTRACT(MONTH FROM cohort_month)::int)
        ) AS month_index

    FROM customer_activity

),

-- 4. Count retained customers per cohort and month
cohort_aggregation AS (

    SELECT
        cohort_month,
        month_index,
        COUNT(DISTINCT customer_id) AS retained_customers
    FROM customer_retention
    GROUP BY
        cohort_month,
        month_index

),

-- 5. Calculate initial cohort size (M0)
cohort_size_calc AS (

    SELECT
        cohort_month,
        month_index,
        retained_customers,

        MAX(
            CASE
                WHEN month_index = 0 THEN retained_customers
            END
        ) OVER (
            PARTITION BY cohort_month
        ) AS cohort_size

    FROM cohort_aggregation

),

-- 6. Calculate retention rate
final AS (

    SELECT
        cohort_month,
        month_index,
        retained_customers,
        cohort_size,

        ROUND(
            (
                retained_customers::numeric
                / NULLIF(cohort_size, 0)
            ) * 100,
            2
        ) AS retention_rate

    FROM cohort_size_calc

)

SELECT *
FROM final
