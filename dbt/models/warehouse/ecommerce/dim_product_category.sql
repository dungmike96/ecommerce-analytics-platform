{{ config(materialized='table') }}

SELECT
    category_id,
    parent_category_id,
    category_code,
    category_name,
    display_order,
    category_status,
    CASE
        WHEN category_status = 1 THEN 'Active'
        WHEN category_status = 2 THEN 'Inactive'
        ELSE 'Unknown'
    END AS category_status_name,
    category_image,
    category_content,
    last_ingested_at
FROM {{ ref('stg_nhanh_categories') }}