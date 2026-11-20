# Ecommerce Analytics Platform

Dự án cá nhân xây dựng **end-to-end data platform** cho một công ty ecommerce tại Việt Nam
(bán hàng qua Nhanh.vn, sàn TikTok Shop và website). Dự án đi từ việc kéo dữ liệu từ API,
lưu vào PostgreSQL, mô hình hóa bằng dbt, đến dashboard Power BI cho quản trị.

> **Lưu ý:** tên công ty, tài nguyên cloud và số liệu trong repo này đã được ẩn danh.
> Repo không chứa dữ liệu khách hàng, credential hay số liệu kinh doanh thật.

---

# 1. Bối cảnh và vấn đề

<Viết 3-5 câu bằng lời của bạn. Gợi ý: dữ liệu nằm rời rạc ở nhiều nguồn, báo cáo làm tay mỗi tuần,
số doanh thu giữa các nguồn không khớp nhau, và không ai biết nên tin số nào.
Một chi tiết thật bạn nhớ (người cụ thể, một lần số liệu bị lệch) sẽ thuyết phục hơn mô tả chung.>

Mục tiêu của dự án:

- Gom dữ liệu từ nhiều nguồn về một nơi duy nhất
- Chuẩn hóa business logic trong dbt thay vì rải rác trong Excel hoặc Power BI
- Có kiểm tra tự động (tests) để số liệu báo cáo đối soát được với dữ liệu gốc
- Cung cấp dataset sẵn sàng cho Power BI

---

# 2. Architecture

```text
Nhanh.vn API   GA4   Google Sheets (chi phí)
      │         │          │
      ▼         ▼          ▼
┌───────────────────────────────┐
│ 1. RAW                        │
│ PostgreSQL (schema raw)       │
│ Python ingestion              │
└──────────────┬────────────────┘
               ▼
┌───────────────────────────────┐
│ 2. STAGING          (dbt)     │
│ stg_*                         │
│ Parse JSON, rename, cast      │
└──────────────┬────────────────┘
               ▼
┌───────────────────────────────┐
│ 3. INTERMEDIATE     (dbt)     │
│ int_*                         │
│ Phân loại đơn, làm giàu dữ    │
│ liệu, business transform      │
└──────────────┬────────────────┘
               ▼
┌───────────────────────────────┐
│ 4. WAREHOUSE        (dbt)     │
│ PostgreSQL (data_schema)      │
│ dim_* / fact_*                │
└──────────────┬────────────────┘
               ▼
┌───────────────────────────────┐
│ 5. ANALYTICS        (dbt)     │
│ fct_* / customer_* / cohort   │
│ GA4 daily marts               │
└──────────────┬────────────────┘
               ▼
          Power BI
```

Sơ đồ chi tiết hơn: [`docs/architecture.png`](docs/architecture.png)

## Nguyên tắc thiết kế

- **RAW** giữ dữ liệu gần với API gốc nhất (lưu JSON payload), không sửa dữ liệu.
- **dbt** chịu trách nhiệm cleaning, transformation, business logic, dimensional modeling.
- **Power BI** không đọc trực tiếp JSON từ RAW, chỉ đọc từ layer `warehouse` và `analytics`.
- Ingestion dùng **UPSERT** nên chạy lại nhiều lần không nhân đôi dữ liệu.

---

# 3. Technology Stack

| Component | Technology |
|---|---|
| Nguồn dữ liệu | Nhanh.vn API v3.0, Google Analytics 4, Google Sheets |
| Ingestion | Python |
| Database | PostgreSQL |
| Transformation | dbt |
| BI | Power BI |
| Automation | PowerShell, backup PostgreSQL lên AWS S3 |
| AI agents (thử nghiệm) | n8n + Ollama (Docker Compose) |
| Version Control | Git |

---

# 4. Project Structure

```text
ecommerce-analytics-platform/
│
├── ingestion/            Python ingestion (Nhanh.vn, GA4, Google Sheets)
├── dbt/
│   ├── models/
│   │   ├── staging/
│   │   ├── intermediate/
│   │   ├── warehouse/
│   │   └── analytics/
│   ├── tests/            singular tests (đối soát, grain, KPI contract)
│   ├── macros/
│   └── docs/             mapping dữ liệu staging
├── sql/
│   ├── migrations/
│   ├── quality_checks/
│   └── diagnostics/
├── automation/           PowerShell: chạy pipeline, backup lên S3
├── ai_agents/            n8n + Ollama (Docker Compose)
├── docs/                 sơ đồ kiến trúc, ảnh dashboard
├── .env.example
├── requirements.txt
└── README.md
```

---

# 5. dbt Layers

## Staging (`stg_*`)

Parse JSON từ RAW, đổi tên cột, ép kiểu dữ liệu, chuẩn hóa timestamp.

| Nhóm | Model |
|---|---|
| Nhanh.vn | `stg_nhanh_orders`, `stg_nhanh_order_items`, `stg_nhanh_order_gifts`, `stg_nhanh_customers`, `stg_nhanh_products`, `stg_nhanh_inventory`, `stg_nhanh_categories` |
| GA4 | `stg_ga4_events_daily`, `stg_ga4_landing_pages_daily`, `stg_ga4_traffic_acquisition_daily` |
| Chi phí | `stg_google_sheets_expenses` |

## Intermediate (`int_*`)

Join dữ liệu, phân loại đơn hàng, tính toán logic dùng lại nhiều nơi.

`int_nhanh_orders_enriched`, `int_nhanh_orders_classified`, `int_nhanh_order_items_enriched`

## Warehouse (`dim_*`, `fact_*`)

Schema đích: `data_schema`.

| Loại | Model |
|---|---|
| Dimension | `dim_channel`, `dim_customers`, `dim_date`, `dim_time`, `dim_product`, `dim_product_category`, `dim_status` |
| Fact | `fact_orders`, `fact_order_items`, `fact_inventory_snapshot` |

## Analytics

| Nhóm | Model |
|---|---|
| Doanh thu và kênh | `fct_daily_sales`, `fct_channel_performance`, `fct_product_performance`, `fct_status_performance` |
| Khách hàng | `customer_rfm`, `customer_lifetime_value`, `cohort_analytics` |
| GA4 | `ga4_acquisition_daily`, `ga4_events_daily`, `ga4_landing_page_daily` |

---

# 6. Data Quality

Dự án không dừng ở việc "build bảng", mà kiểm tra để số liệu đối soát được.

- **28 singular tests** trong `dbt/tests/` (đếm theo danh sách file), gồm các nhóm:
  - **Reconciliation:** số liệu ở layer sau phải khớp layer trước
    (ví dụ `fct_daily_sales` khớp `fact_orders`, `fact_order_items` khớp `int_*`)
  - **Grain:** mỗi bảng có đúng một dòng cho mỗi khóa nghiệp vụ
  - **Công thức tài chính:** net sales, order net không được lệch công thức
  - **KPI contract:** các KPI dùng trong BI phải đúng định nghĩa đã thống nhất
- **SQL quality checks** cho RAW: `sql/quality_checks/`
- **Migrations** lưu trong `sql/migrations/` để mọi thay đổi database truy vết được qua Git

---

# 7. Ingestion

| Script | Nguồn | Ghi chú |
|---|---|---|
| `ingest_nhanh_orders.py` | Nhanh.vn | Historical backfill chia theo time window, sau đó incremental |
| `ingest_nhanh_customers.py` | Nhanh.vn | |
| `ingest_nhanh_products_inventory.py` | Nhanh.vn | Sản phẩm và tồn kho |
| `ingest_nhanh_categories.py` | Nhanh.vn | |
| `ingest_ga4_mkt.py` | Google Analytics 4 | |
| `ingest_google_sheets_expenses.py` | Google Sheets | Chi phí |

Cơ chế chính:

- **Watermark:** lưu mốc thời gian lần chạy trước, lần sau chỉ lấy dữ liệu thay đổi
- **UPSERT** theo khóa nghiệp vụ (ví dụ `order_id`): đơn mới thì INSERT, đơn đã đổi thì UPDATE
- Credential đọc từ biến môi trường, không hard-code trong source

---

# 8. Automation

| File | Việc |
|---|---|
| `automation/run_data_pipeline.ps1` | Chạy các luồng ingestion rồi dbt |
| `automation/test_run_data_pipeline_diagnostic.ps1` | Bản chạy có báo cáo chẩn đoán lỗi |
| `automation/run_backup_s3.ps1` | Backup PostgreSQL và upload lên S3 (AWS CLI) |

---

# 9. Dashboard (Power BI)

| Trang | Nội dung |
|---|---|
| Overview | <điền: KPI chính của trang> |
| Marketing | <điền> |
| Customer Behavior | <điền: RFM, cohort> |
| Inventory | <điền> |

<!-- Thay bằng ảnh thật sau khi xuất -->
![Overview](docs/dashboard/overview.png)

---

# 10. Kết quả

<Chỉ điền số bạn tự đo được. Ví dụ định dạng:
- Báo cáo doanh thu tuần: từ <X giờ làm tay> xuống <Y phút>
- Số model dbt: <N>, số test: 28
Nếu chưa có số đo, ghi rõ "chưa đo" thay vì ước lượng.>

---

# 11. Cách chạy local

> Cần PostgreSQL của riêng bạn và credential API riêng.
> Repo này chỉ chứa code, không kèm dữ liệu.

## Tạo virtual environment (Windows PowerShell)

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r requirements.txt
```

## Cấu hình biến môi trường

```powershell
Copy-Item .env.example .env
```

Điền giá trị vào `.env` (file này đã nằm trong `.gitignore`, **không bao giờ commit**).

## Chạy ingestion

```powershell
python .\ingestion\ingest_nhanh_orders.py
```

## Chạy dbt

Cần tự tạo file `profiles.yml` của dbt trỏ tới PostgreSQL của bạn (không có trong repo).

```powershell
cd .\dbt
dbt deps
dbt debug
dbt build
```

---

# 12. Trạng thái dự án

**Đã xây dựng (có trong repo):**

- Ingestion từ Nhanh.vn, GA4, Google Sheets vào RAW
- dbt 4 layer: staging, intermediate, warehouse, analytics
- 28 singular tests đối soát
- Automation PowerShell và backup S3
# 13. Tác giả

**Nguyễn Văn Dũng** · Analytics Engineer / Data Analyst
https://www.linkedin.com/in/dungnv13496/ · nguyenvandung13896@gmail.com
