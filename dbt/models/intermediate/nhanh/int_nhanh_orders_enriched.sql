-- ============================================================
-- INTERMEDIATE
-- Nhanh orders enriched with aggregated item metrics
--
-- Grain:
--   1 row = 1 order_id
-- ============================================================

WITH orders AS (

    SELECT *
    FROM {{ ref('stg_nhanh_orders') }}

),

items AS (

    SELECT *
    FROM {{ ref('int_nhanh_order_items_enriched') }}

),

item_by_order AS (

    SELECT
        order_id,

        COUNT(*) AS total_item_lines,

        SUM(quantity) AS total_quantity,

        SUM(gross_sales_amount)
            AS gross_sales_amount,

        SUM(discount_amount)
            AS discount_amount,

        SUM(net_sales_amount)
            AS net_sales_amount,

        SUM(estimated_cogs)
            AS estimated_cogs,

        SUM(estimated_gross_profit)
            AS estimated_gross_profit,

        COUNT(*) FILTER (
            WHERE has_cost = FALSE
        ) AS zero_cost_lines,

        COUNT(*) FILTER (
            WHERE matches_expected_net_formula = FALSE
        ) AS net_formula_mismatch_lines

    FROM items

    GROUP BY order_id

),

final AS (

    SELECT

        -- =========================
        -- ORDER KEYS
        -- =========================

        o.order_id,
        o.customer_id,
        o.depot_id,
        o.sale_channel_id,
	o.marketplace_order_id,
	o.marketplace_shop_id,

        -- =========================
        -- ORDER STATUS
        -- =========================

        o.status_id,

        -- =========================
        -- TIME
        -- =========================

        o.created_at,
        o.updated_at,

        -- =========================
        -- SOURCE ORDER MONEY
        -- =========================

        o.cod_amount,
        o.business_payment,
        -- =========================
        -- TRAFFIC SOURCE
        -- =========================
        o.traffic_source,
        o.private_description,
        o.description,

        -- =========================
        -- ITEM AGGREGATES
        -- =========================

        COALESCE(i.total_item_lines, 0)
            AS total_item_lines,

        COALESCE(i.total_quantity, 0)
            AS total_quantity,

        COALESCE(i.gross_sales_amount, 0)
            AS gross_sales_amount,

        COALESCE(i.discount_amount, 0)
            AS discount_amount,

        COALESCE(i.net_sales_amount, 0)
            AS net_sales_amount,

        COALESCE(i.estimated_cogs, 0)
            AS estimated_cogs,

        COALESCE(i.estimated_gross_profit, 0)
            AS estimated_gross_profit,

        -- =========================
        -- DATA QUALITY
        -- =========================

        COALESCE(i.zero_cost_lines, 0)
            AS zero_cost_lines,

        COALESCE(i.net_formula_mismatch_lines, 0)
            AS net_formula_mismatch_lines,

        CASE
            WHEN i.order_id IS NOT NULL THEN TRUE
            ELSE FALSE
        END AS has_items

    FROM orders AS o

    LEFT JOIN item_by_order AS i
        ON o.order_id = i.order_id

)

SELECT *
FROM final