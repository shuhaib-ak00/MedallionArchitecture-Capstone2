# 🚕 NYC Taxi Database Analytics — Capstone Project 2

Project ini membangun **database analytics** untuk data New York Yellow Taxi (Januari 2026) menggunakan **PostgreSQL** dengan pendekatan **medallion architecture** (Bronze → Silver → Gold). Data hasil extract dari Capstone Project 1 dimuat ke database, ditransformasi menggunakan SQL murni, lalu diolah menjadi data mart dan view yang siap dipakai untuk menjawab pertanyaan bisnis seputar demand perjalanan, revenue, payment behavior, performa zona pickup/dropoff, dan kualitas data.

Python digunakan sebagai **orchestration layer** (extract file, load ke bronze, mencatat audit), sedangkan seluruh **logic transformasi dan analisis** (DDL, constraint, join, CTE, window function) ditulis eksplisit dalam file `.sql`.

---

## 📌 Daftar Isi
1. [Fitur Utama](#-fitur-utama)
2. [Struktur Folder](#-struktur-folder)
3. [Arsitektur Medallion](#-arsitektur-medallion-bronze--silver--gold)
4. [Desain Database & ERD](#-desain-database--erd)
5. [Prasyarat](#-prasyarat)
6. [Cara Menjalankan Project](#-cara-menjalankan-project)
7. [Menjalankan Pipeline Otomatis](#-menjalankan-pipeline-otomatis-satu-command)
8. [Business Questions](#-business-questions)
9. [Audit & Logging](#-audit--logging)
10. [Kendala Teknis & Asumsi](#-kendala-teknis--asumsi)

---

## ✨ Fitur Utama

- Load data raw (Parquet & CSV) hasil extract Capstone Project 1 ke PostgreSQL layer **bronze**.
- Transformasi data ke layer **silver** menggunakan SQL murni: cleaning, casting tipe data, kolom turunan (`pickup_date`, `pickup_hour`, `is_weekend`, `time_period`, `trip_duration_minutes`), mapping payment type, dan join ke zone lookup.
- Pencatatan baris invalid ke `silver.data_quality_issues`.
- Layer **gold** berupa view (`gold.vw_trip_enriched`, `gold.vw_zone_performance`) dan tabel mart fisik (`gold.mart_daily_trip_summary`) untuk reporting.
- 10+ query business questions memakai CTE, subquery, join, dan window function (`SUM() OVER`, `LAG()`, `RANK()`, dsb).
- Audit trail proses load/transform di `audit.load_audit` (nama tabel target, status, jumlah baris, waktu eksekusi).
- Pipeline end-to-end dijalankan dengan satu command lewat `run_database_pipeline.sh`, dengan log tersimpan di folder `logs/`.
- Seluruh service database dijalankan via **Docker Compose**.

---

## 📁 Struktur Folder

```
capstone_project_2/
├── data/
│   └── raw/                        # hasil download parquet & csv (tidak di-commit ke git)
├── db/
│   └── init/
│       ├── 01_schema.sql           # membuat schema bronze, silver, gold, audit
│       ├── 02_bronze_load.sql      # DDL tabel bronze
│       ├── ddl_audit.sql           # DDL schema & tabel audit.load_audit
│       ├── 03_silver_transform.sql # transformasi bronze -> silver + data quality
│       └── 04_gold_mart.sql        # view & tabel mart gold
├── db/queries/ (atau root)
│   └── 01_business_question.sql    # kumpulan query business questions
├── scripts/
│   ├── extract_data.py             # download raw data (parquet & csv) jika belum ada
│   ├── load_to_bronze.py           # load parquet/csv ke tabel bronze via COPY
│   ├── audit.py                    # LoadAuditRepository, mencatat proses ke audit.load_audit
│   └── run_database_pipeline.sh    # automation end-to-end pipeline
├── dockerfile                      # image python-app (opsional, untuk eksekusi python di container)
├── docker-compose.yaml             # service postgres-db (+ python-app)
├── requirements.txt                # dependency python
└── README.md
```

> Folder `logs/` akan otomatis dibuat oleh `run_database_pipeline.sh` untuk menyimpan log tiap eksekusi pipeline.

---

## 🥉🥈🥇 Arsitektur Medallion (Bronze → Silver → Gold)

**Bronze** — data mentah hasil extract, struktur kolom mengikuti file sumber:
- `bronze.raw_taxi_trips`
- `bronze.raw_taxi_zones`

**Silver** — data bersih, tervalidasi, dan sudah punya kolom turunan:
- `silver.taxi_trips_cleaned` — trip yang lolos validasi (fare/distance/passenger/total/tip ≥ 0), plus kolom `pickup_date`, `pickup_hour`, `pickup_day_name`, `is_weekend`, `time_period`, `trip_duration_minutes`, dan `payment_type_label`.
- `silver.taxi_zones` — lookup zona taxi (location_id, borough, zone, service_zone).
- `silver.data_quality_issues` — baris yang tidak valid, disimpan sebagai JSON beserta `error_type`.

**Gold** — data mart & view siap pakai untuk analisis/reporting:
- `gold.vw_trip_enriched` — trip + pickup/dropoff zone + payment label + time attributes.
- `gold.vw_zone_performance` — ringkasan performa tiap zone (total pickup/dropoff trip, revenue, avg fare, avg tip).
- `gold.mart_daily_trip_summary` — tabel fisik ringkasan harian (total trip, revenue, avg fare, avg distance, avg duration), diakses juga lewat `gold.vw_daily_trip_summary`.

Alur data:
```
Extract (Capstone 1) → data/raw/*.parquet & *.csv
    → Python load_to_bronze.py → bronze.raw_taxi_trips, bronze.raw_taxi_zones
    → SQL 03_silver_transform.sql → silver.taxi_trips_cleaned, silver.taxi_zones, silver.data_quality_issues
    → SQL 04_gold_mart.sql → gold.vw_trip_enriched, gold.vw_zone_performance, gold.mart_daily_trip_summary
    → SQL 01_business_question.sql → jawaban pertanyaan bisnis
```

Setiap tahap load/transform dicatat ke `audit.load_audit` melalui `scripts/audit.py`.

---

## 🗂 Desain Database & ERD

**Schema:** `bronze`, `silver`, `gold`, `audit`

**Constraint yang diterapkan:**
- Primary key: `silver.taxi_trips_cleaned.trip_id`, `silver.taxi_zones.location_id`, `gold.mart_daily_trip_summary.pickup_date`, `audit.load_audit.audit_id`, dsb.
- Foreign key: `pickup_location_id` dan `dropoff_location_id` pada `silver.taxi_trips_cleaned` mereferensi `silver.taxi_zones.location_id`.
- Not null: kolom wajib seperti `pickup_datetime`, `dropoff_datetime`, `error_type`.
- Check constraint: `passenger_count`, `trip_distance`, `fare_amount`, `tip_amount`, `total_amount` tidak boleh negatif.

Relasi singkat (ERD tekstual):

```
silver.taxi_zones (location_id PK)
        │ 1
        │
        │ *
silver.taxi_trips_cleaned (trip_id PK, pickup_location_id FK, dropoff_location_id FK)
        │
        ▼
gold.vw_trip_enriched / gold.vw_zone_performance / gold.mart_daily_trip_summary
```

*(Diagram visual ERD dapat ditambahkan di `docs/erd.png` jika diperlukan untuk submission.)*

---

## ⚙️ Prasyarat

- Docker Desktop (sudah termasuk Docker Compose v2 — perintah `docker compose`, tanpa strip). Pipeline otomatis mendeteksi `docker compose` dulu lalu fallback ke `docker-compose` v1 bila perlu.
- Python 3.10+ (hanya untuk menjalankan script manual di host; pipeline otomatis `run_database_pipeline.sh` menjalankan Python **di dalam container `python-app`** via `docker exec`)
- Git Bash (Windows) untuk menjalankan `bash scripts/run_database_pipeline.sh`
- Koneksi internet (untuk download raw data dari CloudFront pada tahap extract)
- Resource: data Januari 2026 ± 2.6 juta trip — siapkan RAM ≥ 4 GB, disk bebas ≥ 2 GB (`data/raw` + volume Postgres), dan waktu eksekusi pipeline penuh ± 10–15 menit (tergantung mesin)

---

## 🚀 Cara Menjalankan Project

### 1. Clone repository & masuk ke folder project
```bash
git clone <url-repo-anda>
cd capstone_project_2
```

### 2. Install dependency Python (di host)
```bash
python -m venv venv
source venv/bin/activate        # Windows: venv\Scripts\activate
pip install -r requirements.txt
```

### 3. Jalankan database PostgreSQL via Docker Compose
```bash
docker compose up -d     # Docker Desktop baru; bila gagal coba: docker-compose up -d
```
Ini akan menjalankan container `capstone2_postgres` dan mengekspos PostgreSQL di port **5438** (host) → 5432 (container), dengan database `nyc_taxi`, user `admin`, password `adminpassword`.

> Kredensial default di atas hanya untuk keperluan lokal/capstone. Untuk mengganti, ubah `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` di `docker-compose.yaml` (service `postgres-db` dan `python-app` harus sama), lalu `docker compose down -v && docker compose up -d`. Jangan commit kredensial asli ke repo publik.

### 4. Buat schema database
```bash
docker exec -i capstone2_postgres psql -U admin -d nyc_taxi -f /app/db/init/01_schema.sql
docker exec -i capstone2_postgres psql -U admin -d nyc_taxi -f /app/db/init/ddl_audit.sql
docker exec -i capstone2_postgres psql -U admin -d nyc_taxi -f /app/db/init/02_bronze_load.sql
```

### 5. Extract data raw (download parquet & csv)
```bash
python scripts/extract_data.py
```
File akan disimpan ke `data/raw/`. Jika file sudah ada, proses download akan dilewati (idempotent).

### 6. Load data ke layer Bronze
```bash
python scripts/load_to_bronze.py
```
Script ini melakukan `TRUNCATE` + `COPY` ke `bronze.raw_taxi_trips` dan `bronze.raw_taxi_zones` (aman dijalankan berulang tanpa duplikasi), lalu mencatat hasilnya ke `audit.load_audit`.

### 7. Jalankan transformasi Silver
```bash
docker exec -i capstone2_postgres psql -U admin -d nyc_taxi -f /app/db/init/03_silver_transform.sql
```

### 8. Bangun data mart Gold
```bash
docker exec -i capstone2_postgres psql -U admin -d nyc_taxi -f /app/db/init/04_gold_mart.sql
```

### 9. Jalankan query business questions
```bash
docker exec -i capstone2_postgres psql -U admin -d nyc_taxi -f /app/db/queries/01_business_question.sql
```
Atau buka file `01_business_question.sql` langsung menggunakan tool database favorit Anda (DBeaver, pgAdmin, dsb) dengan koneksi ke `localhost:5438`.

---

## 🔁 Menjalankan Pipeline Otomatis (Satu Command)

Seluruh langkah di atas (start database → schema → extract → load bronze → transform silver → build gold) sudah dirangkum dalam satu script:

```bash
bash scripts/run_database_pipeline.sh
```

Script ini akan:
1. Menyalakan Docker Compose (`docker compose up -d`, fallback ke `docker-compose up -d` untuk instalasi lama) dan menunggu PostgreSQL siap via `pg_isready` (maks 60 detik, bukan `sleep` buta).
2. Membuat schema dan DDL (`01_schema.sql`, `ddl_audit.sql`, `02_bronze_load.sql`).
3. Menjalankan `extract_data.py` untuk download raw data.
4. Menjalankan `load_to_bronze.py` untuk load ke bronze (COPY per chunk 100rb baris + validasi kolom), lalu verifikasi fail-fast bahwa `bronze.raw_taxi_trips` dan `bronze.raw_taxi_zones` tidak kosong.
5. Menjalankan `03_silver_transform.sql` lalu mencatat jumlah baris `silver.taxi_trips_cleaned` ke audit.
6. Menjalankan `04_gold_mart.sql` lalu mencatat jumlah baris `gold.mart_daily_trip_summary` ke audit.
7. Menyimpan seluruh log (timestamp + status tiap tahap) ke `logs/pipeline_run_<timestamp>.log`.

Pipeline akan **berhenti (exit 1)** jika salah satu tahap gagal, dan status kegagalan tetap dicatat ke tabel audit.

---

## 📊 Business Questions

Query lengkap ada di `01_business_question.sql`, di antaranya:

1. Jumlah total trip valid pada Januari 2026.
2. Tanggal dengan jumlah trip tertinggi.
3. Borough/zone pickup dengan jumlah trip tertinggi.
4. Rute pickup → dropoff zone paling sering terjadi.
5. Data quality issue terbanyak berdasarkan `error_type`.
6. Tanggal dengan pola data tidak wajar (anomali berbasis rata-rata & standar deviasi).
7. Top 10 pickup zone berdasarkan revenue.
8. Zone dengan pickup tinggi tetapi average tip rendah.
9. Running total revenue per tanggal (window function).
10. Perbandingan revenue harian dengan hari sebelumnya menggunakan `LAG()`.

Query-query ini memanfaatkan **CTE**, **subquery**, **cross join** dengan agregat, serta **window function** (`SUM() OVER`, `LAG() OVER`), sesuai ketentuan Requirement 3.

---

## 🧾 Audit & Logging

- Setiap proses load (bronze) dan transform (silver, gold) dicatat ke tabel `audit.load_audit` dengan kolom: `target_table`, `status` (`SUCCESS`/`FAILED`), `rows_processed`, dan `execution_time`.
- Log eksekusi pipeline (`run_database_pipeline.sh`) disimpan sebagai file teks di folder `logs/`, berisi timestamp dan status setiap tahap.

Cek riwayat audit:
```sql
SELECT * FROM audit.load_audit ORDER BY execution_time DESC;
```

---

## ⚠️ Kendala Teknis & Asumsi

- Seluruh Python pipeline (`extract_data.py`, `load_to_bronze.py`, `audit.py`) dijalankan **di dalam container `python-app`** via `docker exec`, sehingga koneksi DB memakai host `postgres-db:5432`. Script tetap bisa jalan di host (memakai `localhost:5438`, port mapping Docker Compose) karena membaca env `POSTGRES_*` dengan fallback `DB_*`. Pastikan port 5438 tidak dipakai service lain di mesin Anda.
- Data raw (`data/raw/*.parquet`, `*.csv`) tidak di-commit ke GitHub karena ukurannya besar — gunakan `scripts/extract_data.py` untuk mengunduh ulang, atau tambahkan folder tersebut ke `.gitignore`.
- Proses load ke bronze bersifat idempotent (`TRUNCATE` sebelum `COPY` per chunk 100rb baris), sehingga aman dijalankan berulang tanpa menghasilkan data duplikat.
- Payment type di-mapping manual berdasarkan dokumentasi resmi TLC (1=Credit Card, 2=Cash, 3=No Charge, 4=Dispute, 5=Unknown, 6=Voided Trip).
- Baris dengan nilai negatif/NULL, `passenger_count <= 0`, `dropoff < pickup`, atau LocationID orphan (tidak ada di zone lookup) dikeluarkan dari `silver.taxi_trips_cleaned` dan dicatat ke `silver.data_quality_issues` dengan `error_type` spesifik (`Negative ...`, `Null ...`, `Orphan LocationID`, `Invalid Datetime Order`, `Invalid Passenger Count`).
- File log pipeline (`logs/*.log`) disengaja tidak di-commit (aturan `*.log` di `.gitignore`); riwayat eksekusi permanen tersimpan di tabel `audit.load_audit`.
