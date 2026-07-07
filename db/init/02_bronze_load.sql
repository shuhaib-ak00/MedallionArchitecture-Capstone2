CREATE TABLE IF NOT EXISTS bronze.raw_taxi_zones(
	"LocationID" INT,
	"Borough" VARCHAR(255),
	"Zone" VARCHAR(255),
	"service_zone" VARCHAR(255)
);

CREATE TABLE IF NOT EXISTS bronze.raw_taxi_trips(
	"VendorID" FLOAT,
    "tpep_pickup_datetime" TIMESTAMP,
    "tpep_dropoff_datetime" TIMESTAMP,
    "passenger_count" FLOAT,
    "trip_distance" FLOAT,
    "RatecodeID" FLOAT,
    "store_and_fwd_flag" VARCHAR(5),
    "PULocationID" INT,
    "DOLocationID" INT,
    "payment_type" FLOAT,
    "fare_amount" FLOAT,
    "extra" FLOAT,
    "mta_tax" FLOAT,
    "tip_amount" FLOAT,
    "tolls_amount" FLOAT,
    "improvement_surcharge" FLOAT,
    "total_amount" FLOAT,
    "congestion_surcharge" FLOAT,
    "Airport_fee" FLOAT,
    "cbd_congestion_fee" FLOAT
);