SELECT
    sale_channel_id

FROM {{ ref('fct_channel_performance') }}

WHERE
       avg_order_value IS DISTINCT FROM
       ROUND(
           net_sales_amount
           / NULLIF(total_orders, 0),
           2
       )

    OR avg_quantity_per_order IS DISTINCT FROM
       ROUND(
           total_quantity
           / NULLIF(total_orders, 0),
           2
       )

    OR discount_rate_pct IS DISTINCT FROM
       ROUND(
           100.0 * discount_amount
           / NULLIF(gross_sales_amount, 0),
           2
       )

    OR estimated_gross_margin_pct IS DISTINCT FROM
       ROUND(
           100.0 * estimated_gross_profit
           / NULLIF(net_sales_amount, 0),
           2
       )

    OR cod_to_net_sales_pct IS DISTINCT FROM
       ROUND(
           100.0 * cod_amount
           / NULLIF(net_sales_amount, 0),
           2
       )

    OR business_payment_to_net_sales_pct IS DISTINCT FROM
       ROUND(
           100.0 * business_payment
           / NULLIF(net_sales_amount, 0),
           2
       )