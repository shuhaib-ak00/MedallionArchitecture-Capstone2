import os
import pandas as pd
from sqlalchemy import create_engine
from io import StringIO

import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from audit import LoadAuditRepository

class DatabaseConnection:
    def __init__(self):
        # Dukung dua varian nama env: POSTGRES_* (host) dan DB_* (compose lama).
        # Di dalam container python-app, host harus 'postgres-db:5432'.
        # Di host, host harus 'localhost:5438' (port mapping compose).
        self.user = os.getenv('POSTGRES_USER', os.getenv('DB_USER', 'admin'))
        self.password = os.getenv('POSTGRES_PASSWORD', os.getenv('DB_PASSWORD', 'adminpassword'))
        self.host = os.getenv('POSTGRES_HOST', os.getenv('DB_HOST', 'localhost'))
        self.port = os.getenv('POSTGRES_PORT', os.getenv('DB_PORT', '5438'))
        self.db = os.getenv('POSTGRES_DB', os.getenv('DB_NAME', 'nyc_taxi'))
    
    def get_engine(self):
        connection_string = f"postgresql://{self.user}:{self.password}@{self.host}:{self.port}/{self.db}"
        return create_engine(connection_string)
    
class BronzeLoader:
    def __init__(self, engine):
        self.engine = engine

    def load_data(self, file_path, table_name, file_type='parquet', chunksize=100_000):
        print(f"\n[INFO] Memulai proses load data ke table bronze.{table_name}")

        if not os.path.exists(file_path):
            print(f"[ERROR] File {file_path} tidak ditemukan ")
            raise FileNotFoundError(file_path)
        
        try:
            if file_type == "parquet":
                df_full = pd.read_parquet(file_path)
            elif file_type == "csv":
                df_full = pd.read_csv(file_path)
            else:
                print(f"Type file {file_type} tidak didukung")
                raise ValueError(f"Type file {file_type} tidak didukung")

            # Validasi kolom file terhadap tabel bronze sebelum COPY.
            expected = self._expected_columns(table_name)
            if expected:
                missing = [c for c in expected if c not in df_full.columns]
                extra = [c for c in df_full.columns if c not in expected]
                if missing:
                    raise ValueError(f"Kolom hilang di file untuk bronze.{table_name}: {missing}")
                if extra:
                    print(f"[WARN] Kolom ekstra di file (diabaikan): {extra}")
                    df_full = df_full[expected]

            # Bagi dataframe menjadi chunk agar COPY tidak menahan 2.6jt baris di memori sekaligus.
            chunks = [df_full[i:i + chunksize] for i in range(0, len(df_full), chunksize)] or [df_full]
            
            total_rows = 0
            raw_conn = self.engine.raw_connection()
            auditor = LoadAuditRepository(raw_conn)
            target_table_name = f"bronze.{table_name}"

            try:
                with raw_conn.cursor() as cur:
                    print(f"Membersihkan tabel bronze.{table_name} sebelumnya")
                    cur.execute(f"TRUNCATE TABLE bronze.{table_name}")

                    for i, df in enumerate(chunks):
                        if expected:
                            df = df[[c for c in df.columns if c in expected]]
                        row_count = len(df)
                        total_rows += row_count
                        print(f"[INFO] COPY chunk {i + 1}: {row_count} baris...")

                        buffer = StringIO()
                        # NaN -> string kosong agar COPY bisa memetakan ke NULL.
                        df.to_csv(buffer, index=False, header=False, na_rep='')
                        buffer.seek(0)

                        columns = ', '.join([f'"{col}"' for col in df.columns])
                        copy_sql = f"COPY bronze.{table_name} ({columns}) FROM STDIN WITH (FORMAT CSV, NULL '')"
                        cur.copy_expert(copy_sql, buffer)

                raw_conn.commit()
                print(f"[SUKSES] {total_rows} baris data berhasil dimuat ke bronze.{table_name}")

                auditor.log_audit(target_table=target_table_name, status='SUCCESS', rows_processed=total_rows)

            except Exception as e:
                raw_conn.rollback()
                print(f"[ERROR DATABASE] Gagal mengeksekusi erorr: {e}")

                auditor.log_audit(target_table=target_table_name, status='FAILED', rows_processed=0)
                raise
                
            finally:
                raw_conn.close()
        except (FileNotFoundError, ValueError):
            raise
        except Exception as e:
            print(f"[ERROR SYSTEM] Error ini : {e}")
            raise

    @staticmethod
    def _expected_columns(table_name):
        if table_name == 'raw_taxi_trips':
            return ["VendorID", "tpep_pickup_datetime", "tpep_dropoff_datetime",
                    "passenger_count", "trip_distance", "RatecodeID",
                    "store_and_fwd_flag", "PULocationID", "DOLocationID",
                    "payment_type", "fare_amount", "extra", "mta_tax",
                    "tip_amount", "tolls_amount", "improvement_surcharge",
                    "total_amount", "congestion_surcharge", "Airport_fee",
                    "cbd_congestion_fee"]
        if table_name == 'raw_taxi_zones':
            return ["LocationID", "Borough", "Zone", "service_zone"]
        return []


if __name__ == "__main__":
    db = DatabaseConnection()
    engine = db.get_engine()

    loader = BronzeLoader(engine)

    # DATA_PATH bisa menunjuk ke 'data', 'data/raw', atau '/app/data/raw'.
    # Normalisasi: jika belum berakhiran 'raw', anggap perlu ditambah 'raw'.
    raw_env = os.getenv('DATA_PATH', os.path.join('data', 'raw'))
    if os.path.basename(os.path.normpath(raw_env)) == 'raw':
        base_data_path = raw_env
    else:
        base_data_path = os.path.join(raw_env, 'raw')
    parquet_file = os.path.join(base_data_path, 'yellow_tripdata_2026-01.parquet')
    csv_file = os.path.join(base_data_path, 'taxi_zone_lookup.csv')

    loader.load_data(parquet_file, 'raw_taxi_trips', 'parquet')
    loader.load_data(csv_file, 'raw_taxi_zones', 'csv')


