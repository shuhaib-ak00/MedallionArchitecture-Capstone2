import os
import psycopg2
import sys
from datetime import datetime

class LoadAuditRepository:
    def __init__(self, db_connection):
        self.conn = db_connection

    def log_audit(self, target_table: str, status: str, rows_processed: int):
        query = """
            INSERT INTO audit.load_audit (target_table, status, rows_processed, execution_time)
            VALUES (%s, %s, %s, %s)
        """
        execution_time = datetime.now()
        
        try:
            cursor = self.conn.cursor()
            cursor.execute(query, (target_table, status, rows_processed, execution_time))
            self.conn.commit()
            print(f"[AUDIT SUCCESS] Riwayat {target_table} tercatat (Status: {status}, Rows: {rows_processed})")
        except Exception as e:
            self.conn.rollback()
            print(f"[AUDIT FAILED] Gagal mencatat riwayat eksekusi: {e}")
        finally:
            cursor.close()


if __name__ == "__main__":
    if len(sys.argv) == 4:
        target_table = sys.argv[1]
        status = sys.argv[2]
        rows_processed = int(sys.argv[3])
        
        # Konfigurasi Koneksi DB (bisa di-override via env agar jalan di host maupun container)
        try:
            conn = psycopg2.connect(
                host=os.getenv('POSTGRES_HOST', os.getenv('DB_HOST', 'localhost')),
                port=os.getenv('POSTGRES_PORT', os.getenv('DB_PORT', '5438')),
                database=os.getenv('POSTGRES_DB', os.getenv('DB_NAME', 'nyc_taxi')),
                user=os.getenv('POSTGRES_USER', os.getenv('DB_USER', 'admin')),
                password=os.getenv('POSTGRES_PASSWORD', os.getenv('DB_PASSWORD', 'adminpassword')),
            )
            audit_repo = LoadAuditRepository(conn)
            audit_repo.log_audit(target_table, status, rows_processed)
            conn.close()
        except Exception as e:
            print(f"Gagal koneksi untuk audit: {e}")
    else:
        print("Penggunaan: python scripts/audit.py <nama_tabel> <status> <jumlah_baris>")