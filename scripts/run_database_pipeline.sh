#!/bin/bash
export MSYS_NO_PATHCONV=1

mkdir -p logs
LOG_FILE="logs/pipeline_run_$(date +%Y%m%d_%H%M%S).log"

log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_message "=== MEMULAI PIPELINE DATABASE AUTOMATION ==="

# TAHAP 1: START DATABASE
log_message "Tahap 1: Menyalakan infrastruktur database (Docker Compose)..."
docker-compose up -d >> "$LOG_FILE" 2>&1
sleep 10 

# TAHAP 2: SCHEMA
log_message "Tahap 2: Membuat schema database (Bronze, Silver, Gold, Audit)..."
docker exec -i capstone2_postgres psql -U admin -d nyc_taxi -f /app/db/init/01_schema.sql >> "$LOG_FILE" 2>&1 || { log_message "ERROR: Tahap 2 Gagal!"; exit 1; }
docker exec -i capstone2_postgres psql -U admin -d nyc_taxi -f /app/db/init/ddl_audit.sql >> "$LOG_FILE" 2>&1 || { log_message "ERROR: Tahap 2 (Schema Audit) Gagal!"; exit 1; }
# TAHAP 3: EXTRACT & LOAD (BRONZE)
log_message "Tahap 3: Mengunduh data ke lokal (Extract)..."
python scripts/extract_data.py >> "$LOG_FILE" 2>&1 || { log_message "ERROR: Tahap 3 Gagal!"; exit 1; }

log_message "Tahap 4: Memuat data ke Layer Bronze (Load)..."
python scripts/load_to_bronze.py >> "$LOG_FILE" 2>&1 || { log_message "ERROR: Tahap 4 Gagal!"; exit 1; }

# TAHAP 5: TRANSFORMASI KE SILVER
log_message "Tahap 5: Menjalankan transformasi dan pembersihan data ke Layer Silver..."

if docker exec -i capstone2_postgres psql -U admin -d nyc_taxi -f /app/db/init/03_silver_transform.sql >> "$LOG_FILE" 2>&1; then
    
    # Menghitung baris secara dinamis dari database
    SILVER_ROWS=$(docker exec -i capstone2_postgres psql -U admin -d nyc_taxi -tAc "SELECT COUNT(*) FROM silver.taxi_trips_cleaned;")
    
    # script audit.py
    python scripts/audit.py "silver.taxi_trips_cleaned" "SUCCESS" "$SILVER_ROWS" >> "$LOG_FILE" 2>&1
    log_message "Tahap 5 Sukses. Data Silver bersih siap digunakan ($SILVER_ROWS baris tercatat di audit)."

else
    # Jika gagal
    python scripts/audit.py "silver.taxi_trips_cleaned" "FAILED" 0 >> "$LOG_FILE" 2>&1
    log_message "ERROR: Tahap 4 Gagal! Cek log untuk detailnya. Pipeline dihentikan."
    exit 1
fi


# TAHAP 6: GOLD MART
log_message "Tahap 6: Membangun Data Mart di Layer Gold..."
if docker exec -i capstone2_postgres psql -U admin -d nyc_taxi -f /app/db/init/04_gold_mart.sql >> "$LOG_FILE" 2>&1; then
    
    # Menghitung baris dari tabel fisik
    GOLD_ROWS=$(docker exec -i capstone2_postgres psql -U admin -d nyc_taxi -tAc "SELECT COUNT(*) FROM gold.mart_daily_trip_summary;")
    
    # Mengirimkan datanya ke audit
    python scripts/audit.py "gold.mart_daily_trip_summary" "SUCCESS" "$GOLD_ROWS" >> "$LOG_FILE" 2>&1
    
    log_message "Tahap 6 Sukses. Layer Gold siap digunakan untuk analisa ($GOLD_ROWS baris mart harian tercatat di audit)."

else
    python scripts/audit.py "gold.mart_daily_trip_summary" "FAILED" 0 >> "$LOG_FILE" 2>&1
    log_message "ERROR: Tahap 5 Gagal! Cek log untuk detailnya. Pipeline dihentikan."
    exit 1
fi

log_message "=== PIPELINE SELESAI DENGAN SUKSES ==="