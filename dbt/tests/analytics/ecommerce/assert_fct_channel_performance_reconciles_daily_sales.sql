WITH daily AS (

    SELECT
        sale_channel_id,

        SUM(total_orders) AS total_orders,
        SUM(total_quantity) AS total_quantity,

        SUM(gross_sales_amount) AS gross_sales_amount,
        SUM(discount_amount) AS discount_amount,
        SUM(net_sales_amount) AS net_sales_amount,

        SUM(estimated_cogs) AS estimated_cogs,
        SUM(estimated_gross_profit) AS estimated_gross_profit,

        SUM(cod_amount) AS cod_amount,
        SUM(business_payment) AS business_payment

    FROM {{ ref('fct_daily_sales') }}

    GROUP BY sale_channel_id

),

channel AS (

    SELECT
        sale_channel_id,

        total_orders,
        total_quantity,

        gross_sales_amount,
        discount_amount,
        net_sales_amount,

        estimated_cogs,
        estimated_gross_profit,

        cod_amount,
        business_payment

    FROM {{ ref('fct_channel_performance') }}

)

SELECT
    COALESCE(d.sale_channel_id, c.sale_channel_id) AS sale_channel_id

FROM daily AS d

FULL OUTER JOIN channel AS c
    ON d.sale_channel_id = c.sale_channel_id

WHERE
       COALESCE(d.total_orders, 0)
           <> COALESCE(c.total_orders, 0)

    OR COALESCE(d.total_quantity, 0)
           <> COALESCE(c.total_quantity, 0)

    OR COALESCE(d.gross_sales_amount, 0)
           <> COALESCE(c.gross_sales_amount, 0)

    OR COALESCE(d.discount_amount, 0)
           <> COALESCE(c.discount_amount, 0)

    OR COALESCE(d.net_sales_amount, 0)
           <> COALESCE(c.net_sales_amount, 0)

    OR COALESCE(d.estimated_cogs, 0)
           <> COALESCE(c.estimated_cogs, 0)

    OR COALESCE(d.estimated_gross_profit, 0)
           <> COALESCE(c.estimated_gross_profit, 0)

    OR COALESCE(d.cod_amount, 0)
           <> COALESCE(c.cod_amount, 0)

    OR COALESCE(d.business_payment, 0)
           <> COALESCE(c.business_payment, 0)