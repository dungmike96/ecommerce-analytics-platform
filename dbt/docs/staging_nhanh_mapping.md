\# Nhanh.vn Staging Data Mapping



\## Purpose



Tài liệu mô tả grain, source mapping và datatype cho các staging

models được tạo từ `raw.nhanh_orders`.



Source:

\- PostgreSQL database: `data_center`

\- Schema: `raw`

\- Table: `nhanh_orders`

\- JSON payload column: `api_response`



Staging chỉ thực hiện:

\- Extract JSON

\- Rename columns

\- Cast datatype

\- Light cleaning



Không định nghĩa business KPI như revenue, profit hoặc margin tại

staging layer.





\# 1. stg_nhanh_orders



\## Grain



1 row = 1 Nhanh.vn order.



Primary identifier:



`order\_id`



\## Mapping



| Source | Staging column | Datatype |

|---|---|---|

| raw.order\_id | order\_id | BIGINT |

| info.depotId | depot\_id | BIGINT |

| info.pickupDepotId | pickup\_depot\_id | BIGINT |

| info.type | order\_type\_id | INTEGER |

| info.status | status\_id | INTEGER |

| info.createdAt | created\_at | TIMESTAMPTZ |

| info.updatedAt | updated\_at | TIMESTAMPTZ |

| info.confirmedAt | confirmed\_at | TIMESTAMPTZ |

| info.packedAt | packed\_at | TIMESTAMPTZ |

| info.saleId | sale\_id | BIGINT |

| info.saleName | sale\_name | TEXT |

| channel.saleChannel | sale\_channel\_id | INTEGER |

| channel.appOrderId | app\_order\_id | TEXT |

| channel.shopId | shop\_id | BIGINT |

| channel.shopName | shop\_name | TEXT |

| shippingAddress.id | customer\_id | BIGINT |

| shippingAddress.cityId | city\_id | INTEGER |

| shippingAddress.districtId | district\_id | INTEGER |

| shippingAddress.wardId | ward\_id | INTEGER |

| carrier.id | carrier\_id | BIGINT |

| carrier.deliveryAt | delivered\_at | TIMESTAMPTZ |

| carrier.shipFee | ship\_fee | NUMERIC |

| carrier.codFee | cod\_fee | NUMERIC |

| carrier.returnFee | return\_fee | NUMERIC |

| carrier.ecomFee | ecom\_fee | NUMERIC |

| payment.codAmount | cod\_amount | NUMERIC |

| payment.businessPayment | business\_payment | NUMERIC |

| raw.first\_ingested\_at | first\_ingested\_at | TIMESTAMPTZ |

| raw.last\_ingested\_at | last\_ingested\_at | TIMESTAMPTZ |





\# 2. stg\_nhanh\_order\_items



\## Grain



1 row = 1 order product line.



Identifier:



`order\_product\_id`



Current RAW profiling:



\- Total product lines: 79,427

\- orderProductId NULL: 0

\- Unique orderProductId: 79,427



\## Mapping



| Source | Staging column | Datatype |

|---|---|---|

| parent order\_id | order\_id | BIGINT |

| products.orderProductId | order\_product\_id | BIGINT |

| products.productId | product\_id | BIGINT |

| products.typeId | product\_type\_id | INTEGER |

| products.code | product\_code | TEXT |

| products.name | product\_name | TEXT |

| products.quantity | quantity | NUMERIC |

| products.price | unit\_price | NUMERIC |

| products.originalPrice | original\_price | NUMERIC |

| products.priceAfterVAT | price\_after\_vat | NUMERIC |

| products.discount | unit\_discount | NUMERIC |

| products.discountAmount | discount\_amount | NUMERIC |

| products.avgCost | avg\_cost | NUMERIC |

| products.vatPercent | vat\_percent | NUMERIC |

| products.totalAmount | total\_amount | NUMERIC |



Critical fields currently have 0 NULL:

\- product\_id

\- quantity

\- price

\- total\_amount

\- avg\_cost

\- discount\_amount





\# 3. stg\_nhanh\_order\_gifts



\## Grain



1 row = 1 gift line inside an order.



Current RAW profiling:



\- Orders: 43,594

\- Orders containing gifts: 4,417

\- Gift lines: 4,804

\- Product-level gifts: 4,738

\- Order-level gifts: 66

\- Zero-price gifts: 4,236

\- Positive-price gifts: 568



Current candidate key:



`(order\_id, order\_product\_id, product\_id)`



This candidate key is unique for all 4,804 current gift lines.



`gift\_line\_number` should also be preserved from JSON array ordinality

because Nhanh.vn does not provide a dedicated gift-line ID.



\## Mapping



| Source | Staging column | Datatype |

|---|---|---|

| parent order\_id | order\_id | BIGINT |

| array position | gift\_line\_number | INTEGER |

| gifts.orderProductId | order\_product\_id | BIGINT |

| gifts.productId | product\_id | BIGINT |

| gifts.name | gift\_name | TEXT |

| gifts.quantity | quantity | NUMERIC |

| gifts.price | price | NUMERIC |





\# Business Rule Notes



Staging does NOT calculate:



\- revenue

\- net revenue

\- COGS

\- gross profit

\- margin



In particular, `gifts.price` must not automatically be included in

revenue.



Current data contains 568 gift lines where price > 0.



The business meaning of this value must be validated before it is used

in revenue calculations.



Business KPIs will be defined in Intermediate / Warehouse layers.

