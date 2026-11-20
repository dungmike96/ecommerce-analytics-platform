-- ============================================================
-- 15.7.3C
-- BUSINESS RULE TEST
-- No order-level net formula mismatch
--
-- Grain checked:
--   1 row = 1 order
--
-- Purpose:
--   Ensure no order contains an item line classified
--   as INVALID_NET_FORMULA.
--
-- Expected result:
--   0 rows
-- ============================================================

SELECT
    order_id,
    order_date,
    sale_channel_id,
    status_id,
    gross_sales_amount,
    discount_amount,
    net_sales_amount,
    has_net_formula_mismatch

FROM {{ ref('int_nhanh_orders_classified') }}

WHERE has_net_formula_mismatch = TRUE