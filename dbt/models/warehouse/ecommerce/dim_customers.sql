-- ============================================================
-- WAREHOUSE DIMENSION
-- Customers
--
-- Grain:
--   1 row = 1 customer
--
-- Source:
--   stg_nhanh_customers
--
-- Special member:
--   customer_id = 0
--   Unknown / Guest customer
--
-- Dimension type:
--   Type 1 (current state)
-- ============================================================

WITH customers AS (

    SELECT
        customer_id,
        customer_code,
        customer_name,
        customer_type_id,
        gender_id,

        mobile,
        email,
        address,
        birthday,

        started_date,
        points,
        lifetime_purchase_amount,

        sale_name,

        city_id,
        district_id,
        ward_id,

        location_city_id,
        location_ward_id,

        customer_level_id,
        customer_level_name,

        customer_group_id,
        customer_group_name,

        business_name,
        business_address,
        tax_code,

        source_updated_at

    FROM {{ ref('stg_nhanh_customers') }}

),

final AS (

    -- ========================================================
    -- UNKNOWN / GUEST MEMBER
    -- ========================================================

    SELECT

        0::bigint
            AS customer_id,

        'UNKNOWN'
            AS customer_code,

        'Unknown / Guest'
            AS customer_name,

        NULL::integer
            AS customer_type_id,

        NULL::integer
            AS gender_id,

        NULL::text
            AS mobile,

        NULL::text
            AS email,

        NULL::text
            AS address,

        NULL::date
            AS birthday,

        NULL::date
            AS started_date,

        0::bigint
            AS points,

        0::numeric(18,2)
            AS lifetime_purchase_amount,

        NULL::text
            AS sale_name,

        NULL::integer
            AS city_id,

        NULL::integer
            AS district_id,

        NULL::integer
            AS ward_id,

        NULL::integer
            AS location_city_id,

        NULL::integer
            AS location_ward_id,

        NULL::integer
            AS customer_level_id,

        NULL::text
            AS customer_level_name,

        NULL::integer
            AS customer_group_id,

        NULL::text
            AS customer_group_name,

        NULL::text
            AS business_name,

        NULL::text
            AS business_address,

        NULL::text
            AS tax_code,

        NULL::timestamptz
            AS source_updated_at


    UNION ALL


    -- ========================================================
    -- REAL CUSTOMERS
    -- ========================================================

    SELECT
        customer_id,

        customer_code,

        COALESCE(
            customer_name,
            'Unnamed Customer'
        ) AS customer_name,

        customer_type_id,

        gender_id,

        mobile,

        email,

        address,

        birthday,

        started_date,

        COALESCE(points, 0)
            AS points,

        COALESCE(
            lifetime_purchase_amount,
            0
        ) AS lifetime_purchase_amount,

        sale_name,

        city_id,

        district_id,

        ward_id,

        location_city_id,

        location_ward_id,

        customer_level_id,

        customer_level_name,

        customer_group_id,

        customer_group_name,

        business_name,

        business_address,

        tax_code,

        source_updated_at

    FROM customers

    -- Defensive:
    -- 0 is reserved for Unknown / Guest.
    WHERE customer_id <> 0

)

SELECT *
FROM final