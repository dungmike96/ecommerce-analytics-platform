-- ZOSEO Data Platform | STAGING | Google Sheets CHI TIỀN
-- Grain: one populated source row per spreadsheet / sheet / row number.
-- Amount convention: Vietnamese thousands separator '.', decimal separator ','.
-- Validate this convention against actual Sheet values before reporting.

{{ config(materialized='view') }}

WITH source AS (
    SELECT *
    FROM {{ source('google_sheets', 'google_sheets_expenses') }}
    WHERE sheet_name = 'CHI TIỀN'
),
extracted AS (
    SELECT
        spreadsheet_id,
        sheet_name,
        source_row_number,
        row_hash,
        ingested_at,
        NULLIF(BTRIM(row_data ->> 'Nghiệp vụ'), '') AS transaction_type,
        NULLIF(BTRIM(row_data ->> 'Ngày tháng'), '') AS transaction_date_raw,
        NULLIF(BTRIM(row_data ->> 'Chứng từ'), '') AS accounting_document,
        NULLIF(BTRIM(row_data ->> 'Diễn giải'), '') AS description,
        NULLIF(BTRIM(row_data ->> 'Số tiền'), '') AS amount_raw,
        NULLIF(BTRIM(row_data ->> 'Khách hàng-Nhà cung cấp'), '') AS partner_name,
        NULLIF(BTRIM(row_data ->> 'CHI'), '') AS spend_from,
        NULLIF(BTRIM(row_data ->> 'THU'), '') AS income_from,
        NULLIF(BTRIM(row_data ->> 'Người nhận tiền'), '') AS recipient_name,
        NULLIF(BTRIM(row_data ->> 'Địa chỉ'), '') AS address,
        NULLIF(BTRIM(row_data ->> 'Loại Chi'), '') AS expense_category
    FROM source
),
normalized AS (
    SELECT *,
        REPLACE(REPLACE(REPLACE(amount_raw, ' ', ''), '.', ''), ',', '.') AS amount_normalized
    FROM extracted
),
final AS (
    SELECT
        spreadsheet_id,
        sheet_name,
        source_row_number,
        row_hash,
        transaction_type,
        CASE
            WHEN transaction_date_raw ~ '^\d{2}/\d{2}/\d{4}$'
                 AND TO_CHAR(TO_DATE(transaction_date_raw, 'DD/MM/YYYY'), 'DD/MM/YYYY') = transaction_date_raw
                THEN TO_DATE(transaction_date_raw, 'DD/MM/YYYY')
            WHEN transaction_date_raw ~ '^\d{4}-\d{2}-\d{2}$'
                 AND TO_CHAR(TO_DATE(transaction_date_raw, 'YYYY-MM-DD'), 'YYYY-MM-DD') = transaction_date_raw
                THEN TO_DATE(transaction_date_raw, 'YYYY-MM-DD')
            WHEN transaction_date_raw ~ '^\d{5}$'
                THEN DATE '1899-12-30' + transaction_date_raw::integer
            ELSE NULL
        END AS transaction_date,
        accounting_document,
        description,
        CASE
            WHEN amount_normalized ~ '^-?\d+(\.\d+)?$'
                 AND LENGTH(SPLIT_PART(amount_normalized, '.', 1)) <= 16
                THEN amount_normalized::numeric(18,2)
            ELSE NULL
        END AS amount,
        partner_name,
        spend_from,
        income_from,
        recipient_name,
        address,
        expense_category,
        ingested_at
    FROM normalized
)
SELECT * FROM final
