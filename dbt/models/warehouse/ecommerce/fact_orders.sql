-- ============================================================
-- WAREHOUSE FACT
-- Orders
--
-- Grain:
--   1 row = 1 order_id
--
-- Source:
--   int_nhanh_orders_classified
--
-- Business date rule:
--   order_date MUST be derived from created_at
--   using Vietnam business timezone (Asia/Ho_Chi_Minh).
--
-- Important:
--   - created_at / updated_at are timestamps.
--   - order_date represents the BUSINESS DATE when the order
--     was created in Vietnam.
--   - updated_at MUST NOT be used as order_date.
--   - Financial metrics are inherited from Intermediate.
--   - Do NOT recalculate revenue / COGS / gross profit here.
-- ============================================================
{{ config(
    grants = {
        'select': ['zoseo_ai_reader']
    }
) }}

WITH orders AS (

    SELECT *
    FROM {{ ref('int_nhanh_orders_classified') }}

),


-- ============================================================
-- NORMALIZE BUSINESS DATE
--
-- PostgreSQL TIMESTAMPTZ may be displayed/evaluated according
-- to the database/session timezone (often UTC).
--
-- Example:
--   created_at = 2026-10-06 03:00:00+07
--
-- UTC equivalent:
--   2026-10-05 20:00:00+00
--
-- created_at::date could therefore incorrectly become:
--   2026-10-05
--
-- Always convert to Vietnam timezone BEFORE extracting DATE.
-- ============================================================

normalized AS (

    SELECT

        *,

        (
            created_at
            AT TIME ZONE 'Asia/Ho_Chi_Minh'
        )::date AS business_order_date

    FROM orders

),


final AS (

    SELECT

        -- ====================================================
        -- BUSINESS KEY
        -- ====================================================

        order_id,
	-- ====================================================
	-- EXTERNAL MARKETPLACE IDENTIFIERS
	-- ====================================================
	marketplace_order_id,
	marketplace_shop_id,

        -- ====================================================
        -- DIMENSION KEYS
        -- ====================================================

        TO_CHAR(
            business_order_date,
            'YYYYMMDD'
        )::integer AS order_date_key,

        sale_channel_id,

        status_id,

        customer_id,

        depot_id,


        -- ====================================================
        -- ORDER TIMESTAMPS
        -- ====================================================

        business_order_date AS order_date,

        created_at,

        updated_at,
        EXTRACT(HOUR FROM created_at)::int AS created_hour,
        EXTRACT(HOUR FROM created_at)::int AS created_time_key,

        CASE
            WHEN EXTRACT(HOUR FROM created_at) BETWEEN 0 AND 5
                THEN '00:00-05:59 Late Night'

            WHEN EXTRACT(HOUR FROM created_at) BETWEEN 6 AND 8
                THEN '06:00-08:59 Morning'

            WHEN EXTRACT(HOUR FROM created_at) BETWEEN 9 AND 11
                THEN '09:00-11:59 Morning Shopping'

            WHEN EXTRACT(HOUR FROM created_at) BETWEEN 12 AND 13
                THEN '12:00-13:59 Lunch Break'

            WHEN EXTRACT(HOUR FROM created_at) BETWEEN 14 AND 17
                THEN '14:00-17:59 Afternoon'

            WHEN EXTRACT(HOUR FROM created_at) BETWEEN 18 AND 20
                THEN '18:00-20:59 Evening Prime'

            ELSE '21:00-23:59 Night Prime'
        END AS created_time_slot,

        CASE
            WHEN EXTRACT(HOUR FROM created_at) BETWEEN 0 AND 5 THEN 1
            WHEN EXTRACT(HOUR FROM created_at) BETWEEN 6 AND 8 THEN 2
            WHEN EXTRACT(HOUR FROM created_at) BETWEEN 9 AND 11 THEN 3
            WHEN EXTRACT(HOUR FROM created_at) BETWEEN 12 AND 13 THEN 4
            WHEN EXTRACT(HOUR FROM created_at) BETWEEN 14 AND 17 THEN 5
            WHEN EXTRACT(HOUR FROM created_at) BETWEEN 18 AND 20 THEN 6
            ELSE 7
        END AS created_time_slot_sort,

        -- ====================================================
        -- ORDER / ITEM COUNTS
        -- ====================================================

        total_item_lines,

        total_quantity,


        -- ====================================================
        -- FINANCIAL MEASURES
        -- ====================================================

        gross_sales_amount,

        discount_amount,

        net_sales_amount,

        estimated_cogs,

        estimated_gross_profit,

        cod_amount,

        business_payment,


        -- ====================================================
        -- DATA QUALITY / ANALYTICAL FLAGS
        -- ====================================================

        has_items,

        has_zero_cost_items,

        has_net_formula_mismatch,


        -- ====================================================
        -- CHANNEL CLASSIFICATION
        --
        -- Kept in fact temporarily for convenience/debugging.
        -- Canonical BI attributes should come from dim_channel.
        -- ====================================================

        sale_channel_name,

        sale_channel_group,
        traffic_source,
        traffic_source_group,
        adjusted_revenue_amount

    FROM normalized

)


SELECT *
FROM final