
{{ config(materialized='table') }}

-- ============================================================
-- ZOSEO CUSTOMER LIFETIME VALUE & SEGMENTATION
-- Grain: 1 row = 1 customer_id
-- Historical Revenue CLV (not predicted CLV)
--
-- Business rules:
-- Exclude Shopee 42 / TikTok 48
-- Only status_id = 60
-- Only identified customers
--
-- Segmentation:
-- VIP: top 5% CLV, >= 2 orders, recent <= 180 days
-- High Value New: top 20% CLV, 1 order, recent <= 180 days
-- At Risk: recent > 180 days
-- Loyal: >= 3 orders, recent <= 180 days
-- Regular: remaining customers
--
-- Priority:
-- VIP, High Value New, or high-value At Risk
-- ============================================================

WITH eligible_orders AS (

    SELECT
        customer_id,
        order_id,
        order_date,
        net_sales_amount

    FROM {{ ref('fact_orders') }}

    WHERE sale_channel_id NOT IN (42, 48)
      AND status_id = 60
      AND customer_id IS NOT NULL
      AND customer_id <> 0

),

customer_metrics AS (

    SELECT
        customer_id,

        COUNT(DISTINCT order_id) AS total_orders,

        MIN(order_date) AS first_order_date,
        MAX(order_date) AS last_order_date,

        COALESCE(
            SUM(net_sales_amount),
            0
        ) AS lifetime_revenue

    FROM eligible_orders

    GROUP BY customer_id

),

customer_behavior AS (

    SELECT
        *,

        GREATEST(
            CURRENT_DATE - last_order_date::date,
            0
        ) AS recency_days,

        ROUND(
            lifetime_revenue
            / NULLIF(total_orders, 0),
            0
        ) AS avg_order_value,

        CASE
            WHEN total_orders >= 2 THEN 1
            ELSE 0
        END AS repeat_customer_flag

    FROM customer_metrics

),

customer_ranking AS (

    SELECT
        *,

        PERCENT_RANK() OVER (
            ORDER BY lifetime_revenue DESC
        ) AS clv_percent_rank

    FROM customer_behavior

),

customer_segmentation AS (

    SELECT
        *,

        CASE
            WHEN clv_percent_rank <= 0.05
                 AND total_orders >= 2
                 AND recency_days <= 180
                THEN 'VIP'

            WHEN clv_percent_rank <= 0.20
                 AND total_orders = 1
                 AND recency_days <= 180
                THEN 'High Value New'

            WHEN recency_days > 180
                THEN 'At Risk'

            WHEN total_orders >= 3
                 AND recency_days <= 180
                THEN 'Loyal'

            ELSE 'Regular'
        END AS customer_segment

    FROM customer_ranking

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
        clv_percent_rank,

        repeat_customer_flag,
        customer_segment,
-- VIP và khách mới có giá trị cao
        CASE
            WHEN customer_segment IN (
                'VIP',
                'High Value New'
            )
                THEN TRUE
-- Khách có CLV thuộc Top 20% và có nguy cơ rời bỏ
            WHEN customer_segment = 'At Risk'
                 AND clv_percent_rank <= 0.20
                 AND total_orders >= 2
                THEN TRUE
-- Khách từng mua nhiều, doanh thu lớn,
    -- đã hơn 180 ngày không quay lại
    	    WHEN total_orders > 2
                 AND lifetime_revenue > 50000000
                 AND recency_days > 180
                THEN TRUE
            ELSE FALSE
        END AS priority_member_flag,

        CURRENT_TIMESTAMP AS calculated_at

    FROM customer_segmentation

)

SELECT *
FROM final
