WITH orders AS (

    SELECT *
    FROM {{ ref('int_nhanh_orders_enriched') }}

),

with_group AS (

    SELECT
        o.*,

        -- Có ghi chú COD ở cột nào không
        (
            UPPER(COALESCE(o.private_description, '')) ~ '(HẠ|HA) COD'
            OR UPPER(COALESCE(o.description, '')) ~ '(HẠ|HA) COD'
        ) AS has_cod_note,

        -- Số tiền: ưu tiên privateDescription, nếu không có số thì lấy từ description
        COALESCE(
            substring(
                UPPER(COALESCE(o.private_description, ''))
                FROM '(?:HẠ|HA) COD[^0-9]{0,15}([0-9]+)'
            )::numeric,
            substring(
                UPPER(COALESCE(o.description, ''))
                FROM '(?:HẠ|HA) COD[^0-9]{0,15}([0-9]+)'
            )::numeric
        ) AS cod_target_thousand,

        CASE
            WHEN NULLIF(BTRIM(o.traffic_source), '') IS NOT NULL
                THEN BTRIM(o.traffic_source)
            WHEN o.sale_channel_id = 42 THEN 'Shopee'
            WHEN o.sale_channel_id = 48 THEN 'TikTok'
            WHEN o.sale_channel_id = 1  THEN 'Admin'
            WHEN o.sale_channel_id = 2  THEN 'Bán sỉ – chưa xác định nguồn'
            WHEN o.sale_channel_id = 20 THEN 'Facebook – chưa xác định nguồn'
            WHEN o.sale_channel_id = 10 THEN 'API – chưa xác định nguồn'
            ELSE 'Chưa xác định'
        END AS traffic_source_group

    FROM orders AS o

),

classified AS (

    SELECT
        g.*,

        -- CHANNEL CLASSIFICATION
        CASE
            WHEN g.sale_channel_id = 48 THEN 'TIKTOK_UNVERIFIED'
            WHEN g.sale_channel_id = 42 THEN 'SHOPEE_UNVERIFIED'
            WHEN g.sale_channel_id = 1  THEN 'MANUAL_ORDER_UNVERIFIED'
            WHEN g.sale_channel_id = 2  THEN 'WEBSITE_FB_UNVERIFIED'
            ELSE 'UNKNOWN'
        END AS sale_channel_name,

        CASE
            WHEN g.sale_channel_id IN (48, 42) THEN 'MARKETPLACE'
            WHEN g.sale_channel_id = 1         THEN 'MANUAL'
            WHEN g.sale_channel_id = 2         THEN 'OWNED_ONLINE'
            ELSE 'UNKNOWN'
        END AS sale_channel_group,

        -- ITEM FLAGS
        CASE
            WHEN g.has_items = TRUE THEN 'HAS_ITEMS'
            ELSE 'NO_ITEMS'
        END AS item_status,

        -- DATA QUALITY FLAGS
        (g.zero_cost_lines > 0)           AS has_zero_cost_items,
        (g.net_formula_mismatch_lines > 0) AS has_net_formula_mismatch,

        -- FINANCIAL FLAGS
        (g.cod_amount > 0)       AS has_cod_amount,
        (g.business_payment > 0) AS has_business_payment,

        -- DATE ATTRIBUTES
        g.created_at::date                          AS order_date,
        DATE_TRUNC('month', g.created_at)::date     AS order_month,
        EXTRACT(YEAR FROM g.created_at)::int        AS order_year,
        EXTRACT(MONTH FROM g.created_at)::int       AS order_month_number,
        EXTRACT(DOW FROM g.created_at)::int         AS order_day_of_week,

                -- ADJUSTED REVENUE (chỉ áp dụng cho nhóm Đổi hàng + Affiliate)
        CASE
            WHEN g.traffic_source_group = 'Đổi hàng + Affiliate'
                 AND g.cod_target_thousand IS NOT NULL
                THEN g.cod_target_thousand * 1000

            WHEN g.traffic_source_group = 'Đổi hàng + Affiliate'
                 AND g.has_cod_note
                THEN NULL::numeric

            ELSE g.gross_sales_amount
        END AS adjusted_revenue_amount
    FROM with_group AS g

)

SELECT *
FROM classified