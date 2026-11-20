-- ============================================================
-- NHANH.VN ORDER JSON INSPECTION
-- Dùng để khám phá/debug payload API
-- Không dùng để transform production data
-- ============================================================


-- 1. Xem một payload hoàn chỉnh
SELECT
    order_id,
    jsonb_pretty(api_response) AS payload
FROM raw.nhanh_orders
LIMIT 1;


-- 2. Các object cấp cao nhất
SELECT DISTINCT
    jsonb_object_keys(api_response) AS json_field
FROM raw.nhanh_orders
ORDER BY json_field;


-- 3. Các field trong info
SELECT DISTINCT
    jsonb_object_keys(api_response -> 'info') AS info_field
FROM raw.nhanh_orders
WHERE jsonb_typeof(api_response -> 'info') = 'object'
ORDER BY info_field;


-- 4. Xem object info
SELECT
    order_id,
    jsonb_pretty(api_response -> 'info') AS info
FROM raw.nhanh_orders
LIMIT 3;


-- 5. Xem object channel
SELECT
    order_id,
    jsonb_pretty(api_response -> 'channel') AS channel
FROM raw.nhanh_orders
LIMIT 10;


-- 6. Xem một số field quan trọng
SELECT
    order_id,
    api_response -> 'info' ->> 'depotId' AS depot_id,
    api_response -> 'info' ->> 'createdAt' AS created_at_epoch,
    api_response -> 'info' ->> 'updatedAt' AS updated_at_epoch,
    api_response -> 'info' ->> 'confirmedAt' AS confirmed_at_epoch,
    api_response -> 'info' ->> 'status' AS status
FROM raw.nhanh_orders
ORDER BY order_id DESC
LIMIT 20;

-- ------------------------------------------------------------
-- 7. Các field thực tế trong shippingAddress
-- ------------------------------------------------------------
SELECT DISTINCT
    jsonb_object_keys(api_response -> 'shippingAddress') AS shipping_address_field
FROM raw.nhanh_orders
WHERE jsonb_typeof(api_response -> 'shippingAddress') = 'object'
ORDER BY shipping_address_field;


-- ------------------------------------------------------------
-- 8. Xem mẫu shippingAddress
-- ------------------------------------------------------------
SELECT
    order_id,
    jsonb_pretty(api_response -> 'shippingAddress') AS shipping_address
FROM raw.nhanh_orders
WHERE jsonb_typeof(api_response -> 'shippingAddress') = 'object'
LIMIT 10;

-- ------------------------------------------------------------
-- 9. Các field thực tế trong carrier
-- ------------------------------------------------------------
SELECT DISTINCT
    jsonb_object_keys(api_response -> 'carrier') AS carrier_field
FROM raw.nhanh_orders
WHERE jsonb_typeof(api_response -> 'carrier') = 'object'
ORDER BY carrier_field;


-- ------------------------------------------------------------
-- 10. Xem mẫu carrier
-- ------------------------------------------------------------
SELECT
    order_id,
    jsonb_pretty(api_response -> 'carrier') AS carrier
FROM raw.nhanh_orders
WHERE jsonb_typeof(api_response -> 'carrier') = 'object'
LIMIT 10;


-- ------------------------------------------------------------
-- 11. Các field thực tế trong payment
-- ------------------------------------------------------------
SELECT DISTINCT
    jsonb_object_keys(api_response -> 'payment') AS payment_field
FROM raw.nhanh_orders
WHERE jsonb_typeof(api_response -> 'payment') = 'object'
ORDER BY payment_field;


-- ------------------------------------------------------------
-- 12. Xem mẫu payment
-- ------------------------------------------------------------
SELECT
    order_id,
    jsonb_pretty(api_response -> 'payment') AS payment
FROM raw.nhanh_orders
WHERE jsonb_typeof(api_response -> 'payment') = 'object'
LIMIT 10;

-- ------------------------------------------------------------
-- 13. Kiểm tra số product line trong mỗi order
-- ------------------------------------------------------------
SELECT
    order_id,
    jsonb_array_length(api_response -> 'products') AS product_lines
FROM raw.nhanh_orders
WHERE jsonb_typeof(api_response -> 'products') = 'array'
ORDER BY product_lines DESC
LIMIT 20;

-- ------------------------------------------------------------
-- 14. Xem products[] của một số order
-- ------------------------------------------------------------
SELECT
    order_id,
    jsonb_pretty(api_response -> 'products') AS products
FROM raw.nhanh_orders
WHERE jsonb_typeof(api_response -> 'products') = 'array'
  AND jsonb_array_length(api_response -> 'products') > 0
LIMIT 5;

-- ------------------------------------------------------------
-- 15. Flatten products[] thành từng row
-- ------------------------------------------------------------
SELECT
    o.order_id,
    p.product ->> 'orderProductId' AS order_product_id,
    p.product ->> 'productId' AS product_id,
    p.product ->> 'code' AS product_code,
    p.product ->> 'name' AS product_name,
    p.product ->> 'quantity' AS quantity,
    p.product ->> 'price' AS price,
    p.product ->> 'discountAmount' AS discount_amount,
    p.product ->> 'avgCost' AS avg_cost,
    p.product ->> 'totalAmount' AS total_amount
FROM raw.nhanh_orders AS o
CROSS JOIN LATERAL jsonb_array_elements(
    o.api_response -> 'products'
) AS p(product)
WHERE jsonb_typeof(o.api_response -> 'products') = 'array'
LIMIT 50;
-- ------------------------------------------------------------
-- 16. Các field thực tế bên trong products[]
-- ------------------------------------------------------------
SELECT DISTINCT
    jsonb_object_keys(p.product) AS product_field
FROM raw.nhanh_orders AS o
CROSS JOIN LATERAL jsonb_array_elements(
    o.api_response -> 'products'
) AS p(product)
WHERE jsonb_typeof(o.api_response -> 'products') = 'array'
ORDER BY product_field;

-- ------------------------------------------------------------
-- 17. Mức độ populated của các object chính
-- ------------------------------------------------------------
SELECT
    COUNT(*) AS total_orders,

    COUNT(*) FILTER (
        WHERE jsonb_typeof(api_response -> 'info') = 'object'
    ) AS have_info,

    COUNT(*) FILTER (
        WHERE jsonb_typeof(api_response -> 'channel') = 'object'
    ) AS have_channel,

    COUNT(*) FILTER (
        WHERE jsonb_typeof(api_response -> 'shippingAddress') = 'object'
    ) AS have_shipping_address,

    COUNT(*) FILTER (
        WHERE jsonb_typeof(api_response -> 'carrier') = 'object'
    ) AS have_carrier,

    COUNT(*) FILTER (
        WHERE jsonb_typeof(api_response -> 'payment') = 'object'
    ) AS have_payment,

    COUNT(*) FILTER (
        WHERE jsonb_typeof(api_response -> 'products') = 'array'
          AND jsonb_array_length(api_response -> 'products') > 0
    ) AS have_products

FROM raw.nhanh_orders;

