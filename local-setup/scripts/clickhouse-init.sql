-- Create IoT database
CREATE DATABASE IF NOT EXISTS iot;

-- Create benchmark database (for Flink consumer compatibility)
CREATE DATABASE IF NOT EXISTS benchmark;

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

-- Create raw sensor data table (optimized for integer-based data)
CREATE TABLE IF NOT EXISTS sensor_raw_data (
    sensor_id Int32,           -- Integer sensor ID (optimized)
    sensor_type Int32,         -- Integer sensor type (1=temperature, 2=humidity, etc.)
    location Int32,            -- Integer location ID (optimized)
    temperature Float64,
    humidity Float64,
    pressure Float64,
    battery_level Float64,
    status Int32,              -- Integer status (1=online, 2=offline, 3=maintenance, 4=error)
    timestamp DateTime64(3)    -- High precision timestamp
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

-- ================================================================================
-- BENCHMARK DATABASE SCHEMA (for Flink consumer compatibility)
-- ================================================================================
USE benchmark;

-- Create sensors_local table (optimized for integer-based data)
CREATE TABLE IF NOT EXISTS sensors_local (
    -- Device identifiers (optimized for integer-based data)
    device_id String,           -- converted from sensor_id
    device_type String,         -- converted from sensor_type  
    customer_id String,         -- default mapping
    site_id String,             -- converted from location
    
    -- Location data (simplified - no metadata in optimized schema)
    latitude Float64 DEFAULT 0.0,
    longitude Float64 DEFAULT 0.0,
    altitude Float32 DEFAULT 0.0,
    
    -- Timestamp
    time DateTime64(3),
    
    -- Core sensor readings (from optimized Avro schema)
    temperature Float32,
    humidity Float32,
    pressure Float32,
    battery_level Float32,
    
    -- Status (integer from optimized schema)
    status UInt8,  -- 1=online, 2=offline, 3=maintenance, 4=error
    
    -- Additional metrics (defaults for compatibility)
    co2_level Float32 DEFAULT 400.0,
    noise_level Float32 DEFAULT 50.0,
    light_level Float32 DEFAULT 500.0,
    motion_detected UInt8 DEFAULT 0,
    signal_strength Float32 DEFAULT -50.0,
    memory_usage Float32 DEFAULT 50.0,
    cpu_usage Float32 DEFAULT 30.0,
    error_count UInt32 DEFAULT 0,
    packets_sent UInt64 DEFAULT 0,
    packets_received UInt64 DEFAULT 0,
    bytes_sent UInt64 DEFAULT 0,
    bytes_received UInt64 DEFAULT 0,
    
    -- Calculated columns for fast filtering
    has_alert UInt8 MATERIALIZED (temperature > 35 OR humidity > 80 OR battery_level < 20)
) ENGINE = MergeTree()
PARTITION BY toYYYYMMDD(time)
PRIMARY KEY (device_id, time)
ORDER BY (device_id, time)
TTL time + INTERVAL 7 DAY;

-- Note: For clustered ClickHouse deployments, use:
-- ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/benchmark.sensors_local', '{replica}')
-- And create distributed table:
-- CREATE TABLE IF NOT EXISTS benchmark.sensors_distributed AS benchmark.sensors_local
-- ENGINE = Distributed('iot-cluster', 'benchmark', 'sensors_local', rand());