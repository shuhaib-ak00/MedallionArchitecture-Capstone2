-- Membuat schema audit jika belum ada
CREATE SCHEMA IF NOT EXISTS audit;

-- Membuat tabel load_audit
CREATE TABLE IF NOT EXISTS audit.load_audit (
    audit_id SERIAL PRIMARY KEY,
    target_table VARCHAR(255) NOT NULL,
    status VARCHAR(50) NOT NULL,
    rows_processed INTEGER DEFAULT 0,
    execution_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);