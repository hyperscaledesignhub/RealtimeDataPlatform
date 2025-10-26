-- Create IoT database
CREATE DATABASE IF NOT EXISTS iot;

USE iot;

-- Create sensor_metrics table for aggregated data
CREATE TABLE IF NOT EXISTS sensor_metrics (
    sensor_id String,
    sensor_type String,
    location String,
    window_start DateTime,
    window_end DateTime,
    avg_temperature Float64,
    avg_humidity Float64,
    avg_pressure Float64,
    min_battery Float64,
    max_battery Float64,
    reading_count UInt64,
    processing_time DateTime
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(window_start)
ORDER BY (sensor_id, window_start)
TTL window_start + INTERVAL 90 DAY;

-- Create sensor_alerts table for alert data
CREATE TABLE IF NOT EXISTS sensor_alerts (
    sensor_id String,
    sensor_type String,
    location String,
    temperature Float64,
    humidity Float64,
    battery_level Float64,
    alert_type String,
    alert_time DateTime
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(alert_time)
ORDER BY (sensor_id, alert_time)
TTL alert_time + INTERVAL 30 DAY;

-- Create raw sensor data table (optional, for direct ingestion)
CREATE TABLE IF NOT EXISTS sensor_raw_data (
    sensor_id String,
    sensor_type String,
    location String,
    temperature Float64,
    humidity Float64,
    pressure Float64,
    battery_level Float64,
    status String,
    timestamp DateTime,
    manufacturer String,
    model String,
    firmware_version String,
    latitude Float64,
    longitude Float64
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (sensor_id, timestamp)
TTL timestamp + INTERVAL 7 DAY;

-- Create materialized view for hourly aggregations
CREATE MATERIALIZED VIEW IF NOT EXISTS sensor_hourly_stats
ENGINE = AggregatingMergeTree()
PARTITION BY toYYYYMM(hour_window)
ORDER BY (sensor_id, hour_window)
AS SELECT
    sensor_id,
    sensor_type,
    location,
    toStartOfHour(window_start) as hour_window,
    avgState(avg_temperature) as temperature_avg,
    avgState(avg_humidity) as humidity_avg,
    avgState(avg_pressure) as pressure_avg,
    minState(min_battery) as battery_min,
    maxState(max_battery) as battery_max,
    sumState(reading_count) as total_readings
FROM sensor_metrics
GROUP BY sensor_id, sensor_type, location, hour_window;

-- Create view for latest sensor status
CREATE VIEW IF NOT EXISTS sensor_latest_status AS
SELECT 
    sensor_id,
    sensor_type,
    location,
    argMax(avg_temperature, window_end) as latest_temperature,
    argMax(avg_humidity, window_end) as latest_humidity,
    argMax(avg_pressure, window_end) as latest_pressure,
    argMax(min_battery, window_end) as latest_battery,
    max(window_end) as last_update
FROM sensor_metrics
GROUP BY sensor_id, sensor_type, location;