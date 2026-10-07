import os
import urllib.request

class DataExtractor:
    def __init__(self, raw_data_dir=None):
        # Hormati DATA_PATH bila diberikan (compose: /app/data/raw atau /app/data).
        if raw_data_dir is None:
            raw_env = os.getenv('DATA_PATH', os.path.join('data', 'raw'))
            if os.path.basename(os.path.normpath(raw_env)) == 'raw':
                raw_data_dir = raw_env
            else:
                raw_data_dir = os.path.join(raw_env, 'raw')
        self.raw_data_dir = raw_data_dir
        self._prepare_directory()

    def _prepare_directory(self):

        if not os.path.exists(self.raw_data_dir):
            os.makedirs(self.raw_data_dir)
            print(f"[INFO] Folder '{self.raw_data_dir}' berhasil dibuat.")
        else:
            print(f"[INFO] Folder '{self.raw_data_dir}' sudah tersedia.")

    def download_file(self, url, filename):
        file_path = os.path.join(self.raw_data_dir, filename)

        if os.path.exists(file_path):
            # Logika Hybrid: File sudah ada, lewati proses unduh
            print(f"[SKIP] File '{filename}' sudah tersedia di '{file_path}'. Melewati proses download.")
        else:
            # Logika Hybrid: File tidak ada, mulai unduh
            print(f"[DOWNLOAD] File '{filename}' tidak ditemukan. Mengunduh dari {url}...")
            try:
                urllib.request.urlretrieve(url, file_path)
                print(f"[SUCCESS] Berhasil mengunduh '{filename}'.")
            except Exception as e:
                print(f"[ERROR] Gagal mengunduh '{filename}'. Error: {e}")

if __name__ == "__main__":
    # URL Sumber Data
    TRIP_DATA_URL = "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2026-01.parquet" 
    ZONE_LOOKUP_URL = "https://d37ci6vzurychx.cloudfront.net/misc/taxi+_zone_lookup.csv" 


    extractor = DataExtractor()
    # Eksekusi download Trip New York Taxi (Parquet)
    extractor.download_file(
        url=TRIP_DATA_URL, 
        filename="yellow_tripdata_2026-01.parquet"
    )

    # Eksekusi download Taxi Zone Lookup (CSV)
    extractor.download_file(
        url=ZONE_LOOKUP_URL, 
        filename="taxi_zone_lookup.csv"
    )