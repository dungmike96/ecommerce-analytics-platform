-- ============================================================
-- STAGING: NHANH.VN ORDERS
-- Grain: 1 row = 1 order
-- Source: raw.nhanh_orders
-- ============================================================

with source as (

    select
        order_id,
        api_response,
        first_ingested_at,
        last_ingested_at

    from {{ source('nhanh', 'nhanh_orders') }}

),

extracted as (

    select

        -- ====================================================
        -- ORDER IDENTIFIER
        -- ====================================================

        order_id::bigint as order_id,


        -- ====================================================
        -- ORDER INFO
        -- ====================================================

        nullif(api_response -> 'info' ->> 'depotId', '')::bigint
            as depot_id,

        nullif(api_response -> 'info' ->> 'pickupDepotId', '')::bigint
            as pickup_depot_id,

        nullif(api_response -> 'info' ->> 'type', '')::integer
            as order_type_id,

        nullif(api_response -> 'info' ->> 'status', '')::integer
            as status_id,


        -- ====================================================
        -- ORDER TIMESTAMPS
        -- API stores Unix epoch seconds
        -- ====================================================

        case
            when nullif(
                api_response -> 'info' ->> 'createdAt',
                ''
            ) is not null
            then to_timestamp(
                (api_response -> 'info' ->> 'createdAt')::bigint
            )
        end as created_at,

        case
            when nullif(
                api_response -> 'info' ->> 'updatedAt',
                ''
            ) is not null
            then to_timestamp(
                (api_response -> 'info' ->> 'updatedAt')::bigint
            )
        end as updated_at,

        case
            when nullif(
                api_response -> 'info' ->> 'confirmedAt',
                ''
            ) is not null
            and (api_response -> 'info' ->> 'confirmedAt')::bigint > 0
            then to_timestamp(
                (api_response -> 'info' ->> 'confirmedAt')::bigint
            )
        end as confirmed_at,

        case
            when nullif(
                api_response -> 'info' ->> 'packedAt',
                ''
            ) is not null
            and (api_response -> 'info' ->> 'packedAt')::bigint > 0
            then to_timestamp(
                (api_response -> 'info' ->> 'packedAt')::bigint
            )
        end as packed_at,


        -- ====================================================
        -- SALES PERSON
        -- ====================================================

        nullif(api_response -> 'info' ->> 'saleId', '')::bigint
            as sale_id,

        nullif(api_response -> 'info' ->> 'saleName', '')
            as sale_name,


        -- ====================================================
        -- SALES CHANNEL
        -- ====================================================

	nullif(
    	    api_response -> 'channel' ->> 'saleChannel',
    	    ''
	)::integer as sale_channel_id,
        nullif(
            btrim(api_response #>> '{channel,trafficSource}'),
            ''
        ) AS traffic_source,

	nullif(
    	    btrim(api_response -> 'channel' ->> 'appOrderId'),
    	    ''
	) as marketplace_order_id,

	nullif(
    	    btrim(api_response -> 'channel' ->> 'shopId'),
    	    ''
	) as marketplace_shop_id,

	nullif(
    	    btrim(api_response -> 'channel' ->> 'shopName'),
    	    ''
	) as shop_name,
        -- ====================================================
        -- CUSTOMER / SHIPPING LOCATION
        -- PII fields are intentionally not propagated here.
        -- ====================================================

        nullif(
            api_response -> 'shippingAddress' ->> 'id',
            ''
        )::bigint as customer_id,

        nullif(
            api_response -> 'shippingAddress' ->> 'cityId',
            ''
        )::integer as city_id,

        nullif(
            api_response -> 'shippingAddress' ->> 'districtId',
            ''
        )::integer as district_id,

        nullif(
            api_response -> 'shippingAddress' ->> 'wardId',
            ''
        )::integer as ward_id,


        -- ====================================================
        -- CARRIER
        -- ====================================================

        nullif(
            api_response -> 'carrier' ->> 'id',
            ''
        )::bigint as carrier_id,

        case
            when nullif(
                api_response -> 'carrier' ->> 'deliveryAt',
                ''
            ) is not null
            and (api_response -> 'carrier' ->> 'deliveryAt')::bigint > 0
            then to_timestamp(
                (api_response -> 'carrier' ->> 'deliveryAt')::bigint
            )
        end as delivered_at,

        nullif(
            api_response -> 'carrier' ->> 'shipFee',
            ''
        )::numeric as ship_fee,

        nullif(
            api_response -> 'carrier' ->> 'codFee',
            ''
        )::numeric as cod_fee,

        nullif(
            api_response -> 'carrier' ->> 'returnFee',
            ''
        )::numeric as return_fee,

        nullif(
            api_response -> 'carrier' ->> 'ecomFee',
            ''
        )::numeric as ecom_fee,


        -- ====================================================
        -- PAYMENT
        -- ====================================================

        nullif(
            api_response -> 'payment' ->> 'codAmount',
            ''
        )::numeric as cod_amount,

        nullif(
            api_response -> 'payment' ->> 'businessPayment',
            ''
        )::numeric as business_payment,
        -- ====================================================
        -- NOTE CSKH
        -- ====================================================
        NULLIF(BTRIM(api_response -> 'info' ->> 'privateDescription'), '')
            AS private_description,

        NULLIF(BTRIM(api_response -> 'info' ->> 'description'), '')
            AS description,

        -- ====================================================
        -- INGESTION METADATA
        -- ====================================================

        first_ingested_at,
        last_ingested_at

    from source

),

final as (

    select *
    from extracted

)

select *
from final