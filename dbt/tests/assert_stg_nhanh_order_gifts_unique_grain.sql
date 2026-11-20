-- Fail if more than one row exists for the same
-- (order_id, gift_line_number)

select
    order_id,
    gift_line_number,
    count(*) as row_count

from {{ ref('stg_nhanh_order_gifts') }}

group by
    order_id,
    gift_line_number

having count(*) > 1