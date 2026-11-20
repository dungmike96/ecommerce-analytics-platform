-- ============================================================
-- 15.7.3B
-- BUSINESS RULE TEST
-- No invalid net-sales financial semantics
--
-- Purpose:
--   Ensure every item line follows one of the recognized
--   Nhanh.vn net-sales semantics.
--
-- Valid semantics:
--   1. ZERO_DISCOUNT
--   2. OLD_NET_EQUALS_GROSS
--   3. NEW_NET_EQUALS_GROSS_MINUS_DISCOUNT
--
-- Failure condition:
--   Any row classified as INVALID_NET_FORMULA.
--
-- Expected result:
--   0 rows
-- ============================================================

SELECT
    order_product_id,
    order_id,
    product_id,
    quantity,

    gross_sales_amount,
    discount_amount,
    net_sales_amount,

    net_sales_semantic

FROM {{ ref('int_nhanh_order_items_enriched') }}

WHERE net_sales_semantic = 'INVALID_NET_FORMULA'