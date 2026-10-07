-- tabel lookup zona taxi
CREATE TABLE IF NOT EXISTS silver.taxi_zones (
    location_id INT PRIMARY KEY,
    borough VARCHAR(100),
    zone VARCHAR(255),
    service_zone VARCHAR(100)
);

CREATE TABLE IF NOT EXISTS silver.taxi_trips_cleaned (
    trip_id SERIAL PRIMARY KEY, 
    vendor_id INT,
    pickup_datetime TIMESTAMP NOT NULL,
    dropoff_datetime TIMESTAMP NOT NULL,
    
    -- Foreign Key
    pickup_location_id INT REFERENCES silver.taxi_zones(location_id),
    dropoff_location_id INT REFERENCES silver.taxi_zones(location_id),
    
    -- Metrik Utama (Menggunakan CHECK constraint agar tidak negatif) 
    passenger_count INT CHECK (passenger_count >= 0),
    trip_distance FLOAT CHECK (trip_distance >= 0),
    fare_amount FLOAT CHECK (fare_amount >= 0),
    tip_amount FLOAT CHECK (tip_amount >= 0),
    total_amount FLOAT CHECK (total_amount >= 0),
    
    -- Mapping Payment Type 
    payment_type_label VARCHAR(50), 
    
    -- Kolom Turunan (Derived Columns) hasil transformasi SQL 
    pickup_date DATE,
    pickup_hour INT,
    pickup_day_name VARCHAR(20),
    is_weekend BOOLEAN,
    time_period VARCHAR(20),
    trip_duration_minutes FLOAT
);

CREATE TABLE IF NOT EXISTS silver.data_quality_issues (
    issue_id SERIAL PRIMARY KEY,
    source_table VARCHAR(100),
    error_type VARCHAR(255) NOT NULL, 
    invalid_record_data TEXT, 
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


TRUNCATE TABLE silver.taxi_trips_cleaned RESTART IDENTITY CASCADE;

-- Isi lookup zona dari bronze (TRUNCATE dulu agar idempotent dan FK valid)
TRUNCATE TABLE silver.taxi_zones RESTART IDENTITY CASCADE;

INSERT INTO silver.taxi_zones (location_id, borough, zone, service_zone)
SELECT DISTINCT
    "LocationID"::INT,
    "Borough",
    "Zone",
    service_zone
FROM bronze.raw_taxi_zones
WHERE "LocationID" IS NOT NULL
ON CONFLICT (location_id) DO NOTHING;

-- Memasukkan data bersih ke silver.taxi_trips_cleaned
INSERT INTO silver.taxi_trips_cleaned (
    vendor_id, pickup_datetime, dropoff_datetime, 
    pickup_location_id, dropoff_location_id,
    passenger_count, trip_distance, fare_amount, tip_amount, total_amount,
    payment_type_label, 
    pickup_date, pickup_hour, pickup_day_name, is_weekend, time_period, trip_duration_minutes
)
SELECT 
    t."VendorID"::INT,
    t.tpep_pickup_datetime::TIMESTAMP,
    t.tpep_dropoff_datetime::TIMESTAMP,
    t."PULocationID"::INT,
    t."DOLocationID"::INT,
    t.passenger_count::INT AS passenger_count,
    t.trip_distance::FLOAT,
    t.fare_amount::FLOAT,
    t.tip_amount::FLOAT,
    t.total_amount::FLOAT,
    
    -- Mapping Payment Type
    CASE t.payment_type::INT
        WHEN 1 THEN 'Credit Card'
        WHEN 2 THEN 'Cash'
        WHEN 3 THEN 'No Charge'
        WHEN 4 THEN 'Dispute'
        WHEN 5 THEN 'Unknown'
        WHEN 6 THEN 'Voided Trip'
        ELSE 'Unknown'
    END AS payment_type_label,
    
    DATE(t.tpep_pickup_datetime) AS pickup_date,
    EXTRACT(HOUR FROM t.tpep_pickup_datetime)::INT AS pickup_hour,
    TRIM(TO_CHAR(t.tpep_pickup_datetime, 'Day')) AS pickup_day_name,
    CASE 
        WHEN EXTRACT(ISODOW FROM t.tpep_pickup_datetime) IN (6, 7) THEN TRUE 
        ELSE FALSE 
    END AS is_weekend,
    CASE 
        WHEN EXTRACT(HOUR FROM t.tpep_pickup_datetime) >= 5 AND EXTRACT(HOUR FROM t.tpep_pickup_datetime) < 12 THEN 'Morning'
        WHEN EXTRACT(HOUR FROM t.tpep_pickup_datetime) >= 12 AND EXTRACT(HOUR FROM t.tpep_pickup_datetime) < 17 THEN 'Afternoon'
        WHEN EXTRACT(HOUR FROM t.tpep_pickup_datetime) >= 17 AND EXTRACT(HOUR FROM t.tpep_pickup_datetime) < 21 THEN 'Evening'
        ELSE 'Night'
    END AS time_period,
    EXTRACT(EPOCH FROM (t.tpep_dropoff_datetime::TIMESTAMP - t.tpep_pickup_datetime::TIMESTAMP)) / 60.0 AS trip_duration_minutes

FROM bronze.raw_taxi_trips t
LEFT JOIN bronze.raw_taxi_zones pu_zone ON t."PULocationID" = pu_zone."LocationID"
LEFT JOIN bronze.raw_taxi_zones do_zone ON t."DOLocationID" = do_zone."LocationID"
WHERE t.tpep_pickup_datetime IS NOT NULL
  AND t.tpep_dropoff_datetime IS NOT NULL
  AND t.tpep_dropoff_datetime >= t.tpep_pickup_datetime
  AND t."PULocationID" IS NOT NULL
  AND t."DOLocationID" IS NOT NULL
  AND pu_zone."LocationID" IS NOT NULL
  AND do_zone."LocationID" IS NOT NULL
  AND t.fare_amount IS NOT NULL
  AND t.trip_distance IS NOT NULL
  AND t.passenger_count IS NOT NULL
  AND t.total_amount IS NOT NULL
  AND t.tip_amount IS NOT NULL
  AND t.passenger_count > 0
  AND t.fare_amount >= 0 
  AND t.trip_distance >= 0 
  AND t.total_amount >= 0   
  AND t.tip_amount >= 0;



TRUNCATE TABLE silver.data_quality_issues RESTART IDENTITY CASCADE;


INSERT INTO silver.data_quality_issues (source_table, error_type, invalid_record_data)
SELECT 
    'bronze.raw_taxi_trips' AS source_table,
    

    CASE 
        WHEN t.tpep_pickup_datetime IS NULL OR t.tpep_dropoff_datetime IS NULL THEN 'Null Datetime'
        WHEN t.tpep_dropoff_datetime < t.tpep_pickup_datetime THEN 'Invalid Datetime Order'
        WHEN t."PULocationID" IS NULL OR t."DOLocationID" IS NULL THEN 'Null LocationID'
        WHEN pu_zone."LocationID" IS NULL OR do_zone."LocationID" IS NULL THEN 'Orphan LocationID'
        WHEN t.fare_amount IS NULL OR t.trip_distance IS NULL OR t.passenger_count IS NULL
          OR t.total_amount IS NULL OR t.tip_amount IS NULL THEN 'Null Metric Value'
        WHEN t.passenger_count <= 0 THEN 'Invalid Passenger Count'
        WHEN t.fare_amount < 0 THEN 'Negative Fare Amount'
        WHEN t.trip_distance < 0 THEN 'Negative Trip Distance'
        WHEN t.total_amount < 0 THEN 'Negative Total Amount'
        WHEN t.tip_amount < 0 THEN 'Negative Tip Amount'
        ELSE 'Other Invalid Data'
    END AS error_type,
    
    ROW_TO_JSON(t)::TEXT AS invalid_record_data
FROM bronze.raw_taxi_trips t
LEFT JOIN bronze.raw_taxi_zones pu_zone ON t."PULocationID" = pu_zone."LocationID"
LEFT JOIN bronze.raw_taxi_zones do_zone ON t."DOLocationID" = do_zone."LocationID"
WHERE t.tpep_pickup_datetime IS NULL
   OR t.tpep_dropoff_datetime IS NULL
   OR t.tpep_dropoff_datetime < t.tpep_pickup_datetime
   OR t."PULocationID" IS NULL
   OR t."DOLocationID" IS NULL
   OR pu_zone."LocationID" IS NULL
   OR do_zone."LocationID" IS NULL
   OR t.fare_amount IS NULL
   OR t.trip_distance IS NULL
   OR t.passenger_count IS NULL
   OR t.total_amount IS NULL
   OR t.tip_amount IS NULL
   OR t.passenger_count <= 0
   OR t.fare_amount < 0 
   OR t.trip_distance < 0 
   OR t.total_amount < 0 
   OR t.tip_amount < 0;