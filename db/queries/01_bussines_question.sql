-- 1. Berapa jumlah total trip valid pada Januari 2026
SELECT 
    SUM(total_trip) AS total_valid_trips
FROM gold.vw_daily_trip_summary
WHERE DATE_TRUNC('month', pickup_date) = '2026-01-01';

--2. Tanggal apa yang memiliki jumlah trip tertinggi?
SELECT 
    pickup_date, 
    total_trip 
FROM gold.vw_daily_trip_summary 
ORDER BY total_trip DESC 
LIMIT 1;

--3. Borough atau zone pickup mana yang memiliki jumlah trip tertinggi?
SELECT 
    borough, 
    zone, 
    total_pickup_trip 
FROM gold.vw_zone_performance 
ORDER BY total_pickup_trip DESC 
LIMIT 1;

--4. Rute pickup zone ke dropoff zone mana yang paling sering terjadi?
SELECT 
    pickup_zone, 
    dropoff_zone, 
    COUNT(*) as total_trip 
FROM gold.vw_trip_enriched 
GROUP BY pickup_zone, dropoff_zone 
ORDER BY total_trip DESC 
LIMIT 5;

--5. Tampilkan data quality issue terbanyak berdasarkan error_type.
SELECT 
    error_type, 
    COUNT(*) as issue_count 
FROM silver.data_quality_issues 
GROUP BY error_type 
ORDER BY issue_count DESC;

--6. Cari tanggal dengan pola data tidak wajar (trip count sangat rendah/tinggi dibanding rata-rata).
WITH daily_stats AS (
    SELECT 
        AVG(total_trip) as avg_trip, 
        STDDEV(total_trip) as stddev_trip 
    FROM gold.vw_daily_trip_summary
)
SELECT 
    d.pickup_date, 
    d.total_trip,
    ROUND(s.avg_trip, 0) as average_trip
FROM gold.vw_daily_trip_summary d
CROSS JOIN daily_stats s
WHERE d.total_trip > s.avg_trip + (2 * s.stddev_trip) 
   OR d.total_trip < s.avg_trip - (2 * s.stddev_trip);

--7. Top 10 pickup zone berdasarkan revenue.
SELECT 
    zone, 
    total_revenue 
FROM gold.vw_zone_performance 
ORDER BY total_revenue DESC 
LIMIT 10;

--8. Zone yang memiliki pickup tinggi tetapi average tip rendah.
WITH city_averages AS (
    SELECT 
        AVG(total_pickup_trip) as city_avg_pickup, 
        AVG(average_tip) as city_avg_tip 
    FROM gold.vw_zone_performance
)
SELECT 
    z.zone, 
    z.total_pickup_trip, 
    ROUND(z.average_tip::NUMERIC, 2) as average_tip
FROM gold.vw_zone_performance z
CROSS JOIN city_averages c
WHERE z.total_pickup_trip > c.city_avg_pickup 
  AND z.average_tip < c.city_avg_tip
ORDER BY z.total_pickup_trip DESC;

--9. Running total revenue per tanggal.
SELECT 
    pickup_date, 
    total_revenue, 
    SUM(total_revenue) OVER (ORDER BY pickup_date) AS running_total_revenue 
FROM gold.vw_daily_trip_summary;

--10. Perbandingan revenue hari ini dengan hari sebelumnya menggunakan LAG.
SELECT 
    pickup_date, 
    total_revenue AS revenue_hari_ini, 
    LAG(total_revenue) OVER (ORDER BY pickup_date) AS revenue_kemarin,
    total_revenue - LAG(total_revenue) OVER (ORDER BY pickup_date) AS selisih_revenue
FROM gold.vw_daily_trip_summary;