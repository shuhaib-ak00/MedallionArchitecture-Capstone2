import os
import pandas as pd
from sqlalchemy import create_engine
from io import StringIO

import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from audit import LoadAuditRepository

class DatabaseConnection:
    def __init__(self):
        self.user = os.getenv('POSTGRES_USER', 'admin')
        self.password = os.getenv('POSTGRES_PASSWORD', 'adminpassword')
        self.host = os.getenv('POSTGRES_HOST','localhost')
        self.port = os.getenv('POSTGRES_PORT', '5438')
        self.db = os.getenv('POSTGRES_DB','nyc_taxi')
    
    def get_engine(self):
        connection_string = f"postgresql://{self.user}:{self.password}@{self.host}:{self.port}/{self.db}"
        return create_engine(connection_string)
    
class BronzeLoader:
    def __init__(self, engine):
        self.engine = engine

    def load_data(self, file_path, table_name, file_type='parquet'):
        print(f"\n[INFO] Memulai proses load data ke table bronze.{table_name}")

        if not os.path.exists(file_path):
            print(f"[ERROR] File {file_path} tidak ditemukan ")
            return
        
        try:
            if file_type == "parquet":
                df = pd.read_parquet(file_path)
            elif file_type == "csv":
                df = pd.read_csv(file_path)
            else:
                print(f"Type file {file_type} tidak didukung")
                return
            
            row_count = len(df)
            print(f"[INFO] Berhasil membaca {row_count} baris data")

            buffer = StringIO()
            df.to_csv(buffer, index=False, header=False)
            buffer.seek(0)

            columns = ', '.join([f'"{col}"' for col in df.columns])

            raw_conn = self.engine.raw_connection()

            auditor = LoadAuditRepository(raw_conn)
            target_table_name = f"bronze.{table_name}"

            try:
                with raw_conn.cursor() as cur:
                    print(f"Membersihkan tabel bronze.{table_name} sebelumnya")
                    cur.execute(f"TRUNCATE TABLE bronze.{table_name}")

                    print(f"[INFO] Mengeksekusi perintah COPY ke database...")
                    copy_sql = f"COPY bronze.{table_name} ({columns}) FROM STDIN WITH (FORMAT CSV)"
                    cur.copy_expert(copy_sql, buffer)

                raw_conn.commit()
                print(f"[SUKSES] {row_count} baris data berhasil dimuat ke bronze.{table_name}")

                auditor.log_audit(target_table=target_table_name, status='SUCCESS', rows_processed=row_count)

            except Exception as e:
                raw_conn.rollback()
                print(f"[ERROR DATABASE] Gagal mengeksekusi erorr: {e}")

                auditor.log_audit(target_table=target_table_name, status='FAILED', rows_processed=0)
                
            finally:
                raw_conn.close()
        except Exception as e:
            print(f"[ERROR SYSTEM] Error ini : {e}")


if __name__ == "__main__":
    db = DatabaseConnection()
    engine = db.get_engine()

    loader = BronzeLoader(engine)

    base_data_path = os.getenv('DATA_PATH', 'data/raw')
    parquet_file = os.path.join(base_data_path, 'yellow_tripdata_2026-01.parquet')
    csv_file = os.path.join(base_data_path, 'taxi_zone_lookup.csv')

    loader.load_data(parquet_file, 'raw_taxi_trips', 'parquet')
    loader.load_data(csv_file, 'raw_taxi_zones', 'csv')


