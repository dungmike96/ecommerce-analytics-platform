-- ============================================================
-- INTERMEDIATE
-- Nhanh order items enriched with analytical monetary measures
--
-- Grain:
--   1 row = 1 order_product_id
--
-- Purpose:
--   Enrich staged Nhanh order items with:
--     - gross sales
--     - net sales
--     - estimated COGS
--     - estimated gross profit
--     - cost DQ flags
--     - net-sales semantic classification
--
-- Net-sales semantics discovered from source data:
--
--   ZERO_DISCOUNT
--     discount = 0
--     OLD / NEW semantics are mathematically indistinguishable
--
--   OLD_NET_EQUALS_GROSS
--     net_sales = gross_sales
--
--   NEW_NET_EQUALS_GROSS_MINUS_DISCOUNT
--     net_sales ~= gross_sales - discount
--     tolerance <= 1 VND for decimal discount allocation / rounding
--
--   INVALID_NET_FORMULA
--     does not match any accepted semantic
--
-- IMPORTANT:
--   total_amount remains the source-of-truth net sales value.
--   This model does NOT rewrite financial source values.
-- ============================================================

WITH items AS (

    SELECT *
    FROM {{ ref('stg_nhanh_order_items') }}

),

final AS (

    SELECT

        -- ====================================================
        -- KEYS
        -- ====================================================

        order_product_id,
        order_id,
        product_id,

        -- ====================================================
        -- PRODUCT
        -- ====================================================

        product_code,
        product_name,

        -- ====================================================
        -- QUANTITY
        -- ====================================================

        quantity,

        -- ====================================================
        -- SOURCE MONETARY FIELDS
        -- ====================================================

        unit_price,
        discount_amount,
        avg_cost,
        total_amount,

        -- ====================================================
        -- ANALYTICAL MEASURES
        -- ====================================================

        unit_price * quantity
            AS gross_sales_amount,

        -- Keep Nhanh source value as net sales.
        -- Do NOT reconstruct net sales here.
        total_amount
            AS net_sales_amount,

        avg_cost * quantity
            AS estimated_cogs,

        total_amount - (avg_cost * quantity)
            AS estimated_gross_profit,

        -- ====================================================
        -- COST DATA QUALITY
        -- ====================================================

        CASE
            WHEN avg_cost > 0 THEN TRUE
            ELSE FALSE
        END AS has_cost,

        -- ====================================================
        -- NET-SALES SEMANTIC CLASSIFICATION
        -- ====================================================

        CASE

            -- Required financial fields are missing.
            WHEN unit_price IS NULL
              OR quantity IS NULL
              OR total_amount IS NULL
                THEN 'INVALID_NET_FORMULA'

            -- ------------------------------------------------
            -- ZERO DISCOUNT
            --
            -- gross = gross - discount when discount = 0,
            -- therefore OLD and NEW semantics cannot be
            -- distinguished.
            -- ------------------------------------------------
            WHEN ABS(COALESCE(discount_amount, 0)) <= 0.01
                THEN 'ZERO_DISCOUNT'

            -- ------------------------------------------------
            -- OLD SEMANTIC
            --
            -- Historical Nhanh behavior:
            -- net sales = gross sales
            -- ------------------------------------------------
            WHEN ABS(
                total_amount
                - (unit_price * quantity)
            ) <= 0.01
                THEN 'OLD_NET_EQUALS_GROSS'

            -- ------------------------------------------------
            -- NEW SEMANTIC
            --
            -- Current Nhanh behavior:
            -- net sales = gross sales - discount
            --
            -- Allow <= 1 VND tolerance because RAW data showed
            -- decimal discount allocation / rounding.
            -- ------------------------------------------------
            WHEN ABS(
                total_amount
                - (
                    (unit_price * quantity)
                    - COALESCE(discount_amount, 0)
                )
            ) <= 1
                THEN 'NEW_NET_EQUALS_GROSS_MINUS_DISCOUNT'

            -- ------------------------------------------------
            -- TRUE DQ EXCEPTION
            -- ------------------------------------------------
            ELSE 'INVALID_NET_FORMULA'

        END AS net_sales_semantic,

        -- ====================================================
        -- NET-SALES DATA QUALITY FLAG
        --
        -- TRUE:
        --   matches one of the accepted source semantics.
        --
        -- FALSE:
        --   cannot be explained by known Nhanh behavior.
        -- ====================================================

        CASE

            WHEN unit_price IS NULL
              OR quantity IS NULL
              OR total_amount IS NULL
                THEN FALSE

            -- Zero discount is valid.
            WHEN ABS(COALESCE(discount_amount, 0)) <= 0.01
                THEN TRUE

            -- OLD semantic.
            WHEN ABS(
                total_amount
                - (unit_price * quantity)
            ) <= 0.01
                THEN TRUE

            -- NEW semantic with <= 1 VND tolerance.
            WHEN ABS(
                total_amount
                - (
                    (unit_price * quantity)
                    - COALESCE(discount_amount, 0)
                )
            ) <= 1
                THEN TRUE

            ELSE FALSE

        END AS matches_expected_net_formula

    FROM items

)

SELECT *
FROM final