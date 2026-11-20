WITH warehouse AS (

    SELECT
        sale_channel_id,

        COUNT(*) AS total_orders,
        SUM(total_quantity) AS total_quantity,

        SUM(gross_sales_amount) AS gross_sales_amount,
        SUM(discount_amount) AS discount_amount,
        SUM(net_sales_amount) AS net_sales_amount,

        SUM(estimated_cogs) AS estimated_cogs,
        SUM(estimated_gross_profit) AS estimated_gross_profit,

        SUM(cod_amount) AS cod_amount,
        SUM(business_payment) AS business_payment

    FROM {{ ref('fact_orders') }}

    GROUP BY sale_channel_id

),

analytics AS (

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
    COALESCE(w.sale_channel_id, a.sale_channel_id) AS sale_channel_id

FROM warehouse AS w

FULL OUTER JOIN analytics AS a
    ON w.sale_channel_id = a.sale_channel_id

WHERE
       COALESCE(w.total_orders, 0)
           <> COALESCE(a.total_orders, 0)

    OR COALESCE(w.total_quantity, 0)
           <> COALESCE(a.total_quantity, 0)

    OR COALESCE(w.gross_sales_amount, 0)
           <> COALESCE(a.gross_sales_amount, 0)

    OR COALESCE(w.discount_amount, 0)
           <> COALESCE(a.discount_amount, 0)

    OR COALESCE(w.net_sales_amount, 0)
           <> COALESCE(a.net_sales_amount, 0)

    OR COALESCE(w.estimated_cogs, 0)
           <> COALESCE(a.estimated_cogs, 0)

    OR COALESCE(w.estimated_gross_profit, 0)
           <> COALESCE(a.estimated_gross_profit, 0)

    OR COALESCE(w.cod_amount, 0)
           <> COALESCE(a.cod_amount, 0)

    OR COALESCE(w.business_payment, 0)
           <> COALESCE(a.business_payment, 0)