
-- 1. VIEW: gold.vw_trip_enriched
CREATE OR REPLACE VIEW gold.vw_trip_enriched AS
SELECT
    t.pickup_datetime,
    t.dropoff_datetime,
    t.pickup_date,
    t.pickup_hour,
    t.pickup_day_name,
    t.is_weekend,
    t.time_period,
    t.trip_duration_minutes,
    t.passenger_count,
    t.trip_distance,
    t.fare_amount,
    t.tip_amount,
    t.total_amount,
    t.payment_type_label, 
    pu.borough AS pickup_borough,
    pu.zone AS pickup_zone,
    do_zone.borough AS dropoff_borough,
    do_zone.zone AS dropoff_zone
FROM silver.taxi_trips_cleaned t
LEFT JOIN silver.taxi_zones pu 
    ON t.pickup_location_id = pu.location_id
LEFT JOIN silver.taxi_zones do_zone 
    ON t.dropoff_location_id = do_zone.location_id;


-- 2. VIEW: gold.vw_zone_performance
CREATE OR REPLACE VIEW gold.vw_zone_performance AS
WITH pickup_stats AS (
    SELECT
        pickup_location_id AS location_id,
        COUNT(*) AS total_pickup_trip,
        SUM(total_amount) AS total_revenue,
        AVG(fare_amount) AS average_fare,
        AVG(tip_amount) AS average_tip
    FROM silver.taxi_trips_cleaned
    GROUP BY pickup_location_id
),
dropoff_stats AS (
    SELECT
        dropoff_location_id AS location_id,
        COUNT(*) AS total_dropoff_trip
    FROM silver.taxi_trips_cleaned
    GROUP BY dropoff_location_id
)
SELECT
    z.location_id,
    z.borough,
    z.zone,
    COALESCE(p.total_pickup_trip, 0) AS total_pickup_trip,
    COALESCE(d.total_dropoff_trip, 0) AS total_dropoff_trip,
    COALESCE(p.total_revenue, 0) AS total_revenue,
    COALESCE(p.average_fare, 0) AS average_fare,
    COALESCE(p.average_tip, 0) AS average_tip
FROM silver.taxi_zones z
LEFT JOIN pickup_stats p ON z.location_id = p.location_id
LEFT JOIN dropoff_stats d ON z.location_id = d.location_id;


-- 3. TABEL FISIK: gold.mart_daily_trip_summary
DROP TABLE IF EXISTS gold.mart_daily_trip_summary CASCADE;

CREATE TABLE gold.mart_daily_trip_summary (
    pickup_date DATE PRIMARY KEY,
    total_trip BIGINT, 
    total_revenue NUMERIC(12,2),
    average_fare NUMERIC(10,2),
    average_distance NUMERIC(10,2),
    average_duration NUMERIC(10,2)
);

TRUNCATE TABLE gold.mart_daily_trip_summary;

INSERT INTO gold.mart_daily_trip_summary (
    pickup_date, total_trip, total_revenue, average_fare, average_distance, average_duration
)
SELECT
    pickup_date,
    COUNT(*) AS total_trip,
    SUM(total_amount) AS total_revenue,
    AVG(fare_amount) AS average_fare,
    AVG(trip_distance) AS average_distance,
    AVG(trip_duration_minutes) AS average_duration
FROM silver.taxi_trips_cleaned
WHERE pickup_date IS NOT NULL
GROUP BY pickup_date;


-- 4. VIEW: gold.vw_daily_trip_summary
DROP VIEW IF EXISTS gold.vw_daily_trip_summary;

CREATE VIEW gold.vw_daily_trip_summary AS
SELECT * FROM gold.mart_daily_trip_summary ORDER BY pickup_date;