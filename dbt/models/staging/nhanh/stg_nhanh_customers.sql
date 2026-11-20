-- ============================================================
-- STAGING
-- Nhanh.vn Customers
--
-- Grain:
--   1 row = 1 Nhanh.vn customer
--
-- Source:
--   raw.nhanh_customers
--
-- Purpose:
--   Parse RAW JSON
--   Standardize data types
--   Normalize empty values
-- ============================================================

WITH source AS (

    SELECT
        customer_id,
        api_response,
        source_app_id,
        source_business_id,
        source_updated_at,
        first_ingested_at,
        last_ingested_at

    FROM {{ source('nhanh', 'nhanh_customers') }}

),

parsed AS (

    SELECT

        -- ====================================================
        -- BUSINESS KEY
        -- ====================================================

        customer_id,


        -- ====================================================
        -- CUSTOMER ATTRIBUTES
        -- ====================================================

        NULLIF(
            BTRIM(api_response ->> 'code'),
            ''
        ) AS customer_code,

        NULLIF(
            BTRIM(api_response ->> 'name'),
            ''
        ) AS customer_name,

        CASE
            WHEN (api_response ->> 'type') ~ '^[0-9]+$'
            THEN (api_response ->> 'type')::integer
        END AS customer_type_id,

        CASE
            WHEN (api_response ->> 'gender') ~ '^[0-9]+$'
            THEN (api_response ->> 'gender')::integer
        END AS gender_id,


        -- ====================================================
        -- CONTACT
        -- ====================================================

        NULLIF(
            BTRIM(api_response ->> 'mobile'),
            ''
        ) AS mobile,

        NULLIF(
            BTRIM(api_response ->> 'email'),
            ''
        ) AS email,

        NULLIF(
            BTRIM(api_response ->> 'address'),
            ''
        ) AS address,


        -- ====================================================
        -- DATES
        -- ====================================================

        CASE
            WHEN NULLIF(
                api_response ->> 'birthday',
                ''
            ) ~ '^\d{4}-\d{2}-\d{2}$'
            THEN (api_response ->> 'birthday')::date
        END AS birthday,

        CASE
            WHEN NULLIF(
                api_response ->> 'startedDate',
                ''
            ) ~ '^\d{4}-\d{2}-\d{2}$'
            THEN (api_response ->> 'startedDate')::date
        END AS started_date,


        -- ====================================================
        -- CUSTOMER VALUE
        -- ====================================================

        CASE
            WHEN (api_response ->> 'points')
                    ~ '^-?[0-9]+$'
            THEN (api_response ->> 'points')::bigint
        END AS points,

        CASE
            WHEN (api_response ->> 'totalAmount')
                    ~ '^-?[0-9]+(\.[0-9]+)?$'
            THEN (api_response ->> 'totalAmount')::numeric(18,2)
        END AS lifetime_purchase_amount,


        -- ====================================================
        -- SALES
        -- ====================================================

        NULLIF(
            BTRIM(api_response ->> 'saleName'),
            ''
        ) AS sale_name,


        -- ====================================================
        -- LOCATION - 3 LEVEL ADDRESS
        -- ====================================================

        CASE
            WHEN (
                api_response
                -> 'locations'
                ->> 'cityId'
            ) ~ '^[0-9]+$'
            THEN (
                api_response
                -> 'locations'
                ->> 'cityId'
            )::integer
        END AS city_id,

        CASE
            WHEN (
                api_response
                -> 'locations'
                ->> 'districtId'
            ) ~ '^[0-9]+$'
            THEN (
                api_response
                -> 'locations'
                ->> 'districtId'
            )::integer
        END AS district_id,

        CASE
            WHEN (
                api_response
                -> 'locations'
                ->> 'wardId'
            ) ~ '^[0-9]+$'
            THEN (
                api_response
                -> 'locations'
                ->> 'wardId'
            )::integer
        END AS ward_id,


        -- ====================================================
        -- LOCATION - 2 LEVEL ADDRESS
        -- ====================================================

        CASE
            WHEN (
                api_response
                -> 'location'
                ->> 'cityId'
            ) ~ '^[0-9]+$'
            THEN (
                api_response
                -> 'location'
                ->> 'cityId'
            )::integer
        END AS location_city_id,

        CASE
            WHEN (
                api_response
                -> 'location'
                ->> 'wardId'
            ) ~ '^[0-9]+$'
            THEN (
                api_response
                -> 'location'
                ->> 'wardId'
            )::integer
        END AS location_ward_id,


        -- ====================================================
        -- CUSTOMER LEVEL
        -- Handles object or empty array safely
        -- ====================================================

        CASE
            WHEN jsonb_typeof(
                api_response -> 'level'
            ) = 'object'
            AND (
                api_response
                -> 'level'
                ->> 'id'
            ) ~ '^[0-9]+$'

            THEN (
                api_response
                -> 'level'
                ->> 'id'
            )::integer
        END AS customer_level_id,

        CASE
            WHEN jsonb_typeof(
                api_response -> 'level'
            ) = 'object'

            THEN NULLIF(
                BTRIM(
                    api_response
                    -> 'level'
                    ->> 'name'
                ),
                ''
            )
        END AS customer_level_name,


        -- ====================================================
        -- CUSTOMER GROUP
        -- Handles object or empty array safely
        -- ====================================================

        CASE
            WHEN jsonb_typeof(
                api_response -> 'group'
            ) = 'object'
            AND (
                api_response
                -> 'group'
                ->> 'id'
            ) ~ '^[0-9]+$'

            THEN (
                api_response
                -> 'group'
                ->> 'id'
            )::integer
        END AS customer_group_id,

        CASE
            WHEN jsonb_typeof(
                api_response -> 'group'
            ) = 'object'

            THEN NULLIF(
                BTRIM(
                    api_response
                    -> 'group'
                    ->> 'name'
                ),
                ''
            )
        END AS customer_group_name,


        -- ====================================================
        -- BUSINESS INFORMATION
        -- ====================================================

        CASE
            WHEN jsonb_typeof(
                api_response -> 'business'
            ) = 'object'

            THEN NULLIF(
                BTRIM(
                    api_response
                    -> 'business'
                    ->> 'name'
                ),
                ''
            )
        END AS business_name,

        CASE
            WHEN jsonb_typeof(
                api_response -> 'business'
            ) = 'object'

            THEN NULLIF(
                BTRIM(
                    api_response
                    -> 'business'
                    ->> 'address'
                ),
                ''
            )
        END AS business_address,


        -- ====================================================
        -- TAX
        -- ====================================================

        NULLIF(
            BTRIM(api_response ->> 'taxCode'),
            ''
        ) AS tax_code,


        -- ====================================================
        -- SOURCE METADATA
        -- ====================================================

        source_updated_at,

        first_ingested_at,

        last_ingested_at

    FROM source

)

SELECT *
FROM parsed