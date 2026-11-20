{{ config(materialized='view') }}

SELECT
    category_id,
    NULLIF(api_response ->> 'parentId', '')::bigint
        AS parent_category_id,
    api_response ->> 'code' AS category_code,
    api_response ->> 'name' AS category_name,
    NULLIF(api_response ->> 'order', '')::integer
        AS display_order,
    api_response ->> 'image' AS category_image,
    api_response ->> 'content' AS category_content,
    NULLIF(api_response ->> 'status', '')::integer
        AS category_status,
    last_ingested_at
FROM {{ source('nhanh', 'nhanh_categories') }}