\# Ecommerce Data Warehouse



Data Warehouse phục vụ thu thập, chuẩn hóa và phân tích dữ liệu Ecommerce của công ty.



Nguồn dữ liệu hiện tại:



\- Nhanh.vn API v3.0



Hệ thống được xây dựng để phục vụ:



\- Power BI

\- Grafana

\- Báo cáo quản trị

\- Phân tích dữ liệu Ecommerce



\---



\# 1. Architecture



Luồng dữ liệu tổng thể:



```text

Nhanh.vn API

&#x20;     │

&#x20;     ▼

┌───────────────────────┐

│ 1. RAW                │

│ PostgreSQL            │

│ raw.nhanh\_orders      │

└──────────┬────────────┘

           │

           ▼

┌───────────────────────┐

│ 2. STAGING            │

│ dbt                   │

│ stg\_nhanh\_\*           │

│                       │

│ Cleaning / Casting    │

└──────────┬────────────┘

           │

           ▼

┌───────────────────────┐

│ 3. INTERMEDIATE       │

│ dbt                   │

│ int\_\*                 │

│                       │

│ Business Transform    │

└──────────┬────────────┘

           │

           ▼

┌───────────────────────┐

│ 4. WAREHOUSE / CORE   │

│ PostgreSQL            │

│ data\_schema           │

│                       │

│ dim\_\* / fact\_\*        │

└──────────┬────────────┘

           │
 
           ▼

┌───────────────────────┐

│ 5. ANALYTICS / MART   │

│ dbt                   │

│ analytics             │

│ mart\_\*                │

└──────────┬────────────┘

           │

           ├──────────► Power BI

           │

           └──────────► Grafana

```



\## Nguyên tắc



RAW giữ dữ liệu gần với API gốc nhất.



dbt chịu trách nhiệm:



\- chuẩn hóa

\- cleaning

\- transformation

\- business logic

\- dimensional modeling

\- analytics marts



Power BI và Grafana không đọc trực tiếp JSON từ RAW.



\---



\# 2. Project Structure



```text

ecommerce-dwh/

│

├── ingestion/

│   └── ingest\_nhanh\_orders.py

│

├── dbt/

│   ├── models/

│   │   ├── staging/

│   │   ├── intermediate/

│   │   ├── warehouse/

│   │   └── analytics/

│   │

│   ├── snapshots/

│   ├── macros/

│   ├── tests/

│   └── dbt\_project.yml

│

├── sql/

│   ├── migrations/

│   ├── quality\_checks/

│   └── diagnostics/

│

├── .env.example

├── .gitignore

├── requirements.txt

└── README.md

```



Không commit:



```text

.env

.venv/

target/

logs/

dbt\_packages/

```



\---



\# 3. Technology Stack



| Component | Technology |

|---|---|

| Source | Nhanh.vn API v3.0 |

| Ingestion | Python |

| Database | PostgreSQL |

| Transformation | dbt |

| BI | Power BI |

| Monitoring / Dashboard | Grafana |

| Version Control | Git |



\---



\# 4. Environment Setup



\## Requirements



Project hiện được phát triển với:



```text

Python 3.10

PostgreSQL

Git

```



Python 3.11+ được khuyến nghị cho môi trường production mới.



\---



\## Create Virtual Environment



Windows PowerShell:



```powershell

python -m venv .venv

```



Activate:



```powershell

.\\.venv\\Scripts\\Activate.ps1

```



Kiểm tra:



```powershell

python -c "import sys; print(sys.executable)"

```



Python phải trỏ tới:



```text

ecommerce-dwh\\.venv\\Scripts\\python.exe

```



\---



\# 5. Install Dependencies



```powershell

python -m pip install --upgrade pip

pip install -r requirements.txt

```



Kiểm tra dbt:



```powershell

dbt --version

```



\---



\# 6. Environment Variables



Copy file:



```powershell

Copy-Item .env.example .env

```



Sau đó cấu hình `.env`.



Ví dụ:



```env

NHANH\_APP\_ID=

NHANH\_BUSINESS\_ID=

NHANH\_ACCESS\_TOKEN=



NHANH\_BACKFILL\_START\_DATE=



NHANH\_PAGE\_SIZE=100

NHANH\_HTTP\_TIMEOUT=60

NHANH\_MAX\_RETRIES=3



DB\_HOST=

DB\_PORT=5432

DB\_NAME=

DB\_USER=

DB\_PASSWORD=

```



\## Security



`.env` chứa credential thật và tuyệt đối không được commit lên Git.



Các thông tin sau không được hard-code vào source code:



\- Access Token

\- Database password

\- API credentials



\---



\# 7. RAW Ingestion



Pipeline:



```text

ingestion/ingest\_nhanh\_orders.py

```



Chạy:



```powershell

python .\\ingestion\\ingest\_nhanh\_orders.py

```



Pipeline kết nối:



```text

Nhanh.vn API

&#x20;     ↓

Python ingestion

&#x20;     ↓

PostgreSQL

&#x20;     ↓

raw.nhanh\_orders

```



\---



\# 8. Historical Backfill



Ở lần chạy đầu tiên, pipeline lấy dữ liệu lịch sử từ:



```env

NHANH\_BACKFILL\_START\_DATE

```



Nhanh.vn Order API giới hạn khoảng thời gian truy vấn, vì vậy pipeline chia historical data thành các time windows phù hợp.



Historical backfill chỉ cần thực hiện khi chưa có watermark tương ứng.



\---



\# 9. Incremental Ingestion



Sau khi historical backfill hoàn thành, pipeline sử dụng:



```text

updatedAtFrom

updatedAtTo

```



thay vì tải lại toàn bộ lịch sử.



Luồng:



```text

Watermark

   ↓

updatedAtFrom

   ↓

Nhanh.vn API

   ↓

Orders changed since previous run

   ↓

UPSERT

   ↓

New Watermark

```



Điều này cho phép pipeline xử lý cả:



```text

New Order

  → INSERT



Existing Order changed

  → UPDATE

```



Khóa nghiệp vụ hiện tại:



```text

order\_id

```



\---



\# 10. Watermark



Trạng thái incremental được quản lý tại:



```text

raw.ingestion\_watermark

```



Có thể kiểm tra bằng:



```sql

SELECT \*

FROM raw.ingestion\_watermark;

```



Không tự ý xóa watermark trên production.



Xóa watermark có thể khiến pipeline thực hiện historical backfill lại.



\---



\# 11. RAW Data Quality



Các SQL kiểm tra RAW nằm tại:



```text

sql/quality\_checks/

```



Ví dụ kiểm tra tổng quan:



```sql

SELECT

   COUNT(\*) AS total\_orders,

   COUNT(DISTINCT order\_id) AS unique\_orders,

   COUNT(DISTINCT source\_depot\_id) AS total\_depots,

   MIN(source\_created\_at) AS oldest\_order,

   MAX(source\_created\_at) AS newest\_order,

   MAX(source\_updated\_at) AS latest\_updated

FROM raw.nhanh\_orders;

```



Các kiểm tra quan trọng:



```text

total\_orders

unique\_orders

duplicate order\_id

missing order\_id

missing payload

oldest order

newest order

latest updated

watermark

```



\---



\# 12. Database Migrations



Các thay đổi cấu trúc database được lưu tại:



```text

sql/migrations/

```



Không nên chỉ chạy SQL thay đổi database trong DBeaver mà không lưu lại source SQL.



Mục tiêu là mọi thay đổi quan trọng của database đều có thể truy vết qua Git.



\---



\# 13. Diagnostics



Các query dùng để kiểm tra payload hoặc debug nằm tại:



```text

sql/diagnostics/

```



Ví dụ:



```sql

SELECT

&#x20;   order\_id,

&#x20;   jsonb\_pretty(api\_response)

FROM raw.nhanh\_orders

LIMIT 1;

```



Diagnostic SQL không phải business transformation.



Business transformation phải được thực hiện trong dbt.



\---



\# 14. dbt Setup



Project dbt nằm tại:



```text

dbt/

```



Di chuyển vào project:



```powershell

cd .\\dbt

```



Kiểm tra cấu hình:



```powershell

dbt debug

```



Kết quả yêu cầu:



```text

Connection test: OK

All checks passed!

```



\---



\# 15. dbt Layers



\## Staging



```text

models/staging/

```



Nhiệm vụ:



\- parse JSON từ RAW

\- rename columns

\- cast datatype

\- chuẩn hóa timestamp

\- cleaning cơ bản



Naming:



```text

stg\_nhanh\_orders

stg\_nhanh\_products

stg\_nhanh\_customers

```



\---



\## Intermediate



```text

models/intermediate/

```



Nhiệm vụ:



\- join dữ liệu

\- deduplication

\- business transformations

\- reusable business logic



Naming:



```text

int\_\*

```



\---



\## Warehouse / Core



```text

models/warehouse/

```



Schema đích:



```text

data\_schema

```



Nhiệm vụ:



\- dimensions

\- facts

\- historical modeling

\- business entities



Naming:



```text

dim\_\*

fact\_\*

```



\---



\## Analytics / Mart



```text

models/analytics/

```



Nhiệm vụ:



\- KPI

\- reporting tables/views

\- BI-ready datasets



Naming:



```text

mart\_\*

```



Power BI và Grafana ưu tiên kết nối tới layer này.



\---



\# 16. Run dbt



Kiểm tra connection:



```powershell

cd .\\dbt

dbt debug

```



Chạy models:



```powershell

dbt run

```



Chạy tests:



```powershell

dbt test

```



Có thể chạy:



```powershell

dbt build

```



để build và test resources theo dependency graph.



\---



\# 17. Operational Flow



Quy trình production mục tiêu:



```text

Nhanh.vn

   ↓

Python Ingestion

   ↓

RAW

   ↓

dbt STAGING

   ↓

dbt INTERMEDIATE

   ↓

WAREHOUSE

   ↓

ANALYTICS

   ↓

Power BI / Grafana

```



Ingestion được thiết kế để chạy định kỳ.



Mục tiêu vận hành:



```text

00:00

08:00

16:00

```



Việc scheduling production sẽ được cấu hình trên server/VPS, không phụ thuộc vào laptop cá nhân.



\---



\# 18. Development Workflow



Khi phát triển:



```text

1\. Activate .venv

2\. Pull latest source code

3\. Thay đổi code

4\. Test local

5\. Kiểm tra dbt

6\. Kiểm tra secrets

7\. Commit

8\. Push

```



Ví dụ:



```powershell

.\\.venv\\Scripts\\Activate.ps1



cd .\\dbt

dbt debug

dbt build

```



\---



\# 19. Git Rules



Được commit:



```text

Python source code

dbt models

SQL migrations

SQL quality checks

SQL diagnostics

.env.example

requirements.txt

README.md

```



Không được commit:



```text

.env

password

access token

.venv

database dump

raw company data

dbt target

logs

```



\---



\# 20. Deployment / Handover



Khi chuyển sang máy khác hoặc VPS:



```text

git clone repository

       ↓

create .venv

       ↓

pip install -r requirements.txt

       ↓

create .env

       ↓

configure PostgreSQL

       ↓

dbt debug

       ↓

run ingestion

       ↓

run dbt

       ↓

configure scheduler

```



Nhờ đó project không phụ thuộc vào máy của một cá nhân.



\---



\# 21. Current Data Pipeline Status



Đã triển khai:



\- Nhanh.vn Order API ingestion

\- Historical backfill

\- Pagination

\- RAW PostgreSQL storage

\- JSON payload storage

\- Metadata

\- UPSERT theo order\_id

\- Incremental ingestion theo updatedAt

\- Watermark

\- RAW quality checks

\- dbt PostgreSQL connection



Đang triển khai:



\- dbt Staging

\- Intermediate

\- Warehouse

\- Analytics marts

\- Power BI

\- Grafana

\- Production scheduling



\---



\# 22. Important Operational Rules



1\. Không xóa RAW khi chưa có backup và kế hoạch recovery.

2\. Không xóa watermark tùy ý.

3\. Không hard-code credential.

4\. Không commit `.env`.

5\. Không chỉnh dữ liệu production trực tiếp nếu chưa xác định ảnh hưởng.

6\. Schema change phải được lưu lại bằng migration/dbt code.

7\. Business logic nên nằm trong dbt thay vì Power BI khi có thể.

8\. Dashboard không nên phụ thuộc trực tiếp vào RAW JSON.

