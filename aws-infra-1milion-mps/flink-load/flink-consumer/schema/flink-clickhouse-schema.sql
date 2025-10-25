-- ClickHouse Schema for Flink Consumer - Optimized for Integer Fields
-- Matches the producer's optimized Avro schema

CREATE DATABASE IF NOT EXISTS iot;

-- Raw sensor data table (matches producer schema)
CREATE TABLE IF NOT EXISTS iot.sensor_raw_data
(
    sensor_id Int32,           -- Integer sensor ID
    sensor_type Int32,         -- Integer sensor type (1=temperature, 2=humidity, etc.)
    location Int32,            -- Integer location ID
    temperature Float64,       -- Temperature reading in Celsius
    humidity Float64,          -- Humidity reading as percentage
    pressure Float64,          -- Pressure reading in hPa
    battery_level Float64,     -- Battery level as percentage
    status Int32,              -- Sensor status (1=online, 2=offline, 3=maintenance, 4=error)
    timestamp DateTime64(3)    -- Timestamp in milliseconds since epoch
)
ENGINE = MergeTree()
PARTITION BY toYYYYMMDD(timestamp)
ORDER BY (sensor_id, timestamp)
PRIMARY KEY (sensor_id)
SETTINGS index_granularity = 8192;

-- Sensor alerts table
CREATE TABLE IF NOT EXISTS iot.sensor_alerts
(
    sensor_id Int32,           -- Integer sensor ID
    sensor_type Int32,         -- Integer sensor type
    location Int32,            -- Integer location ID
    temperature Float64,       -- Temperature reading
    humidity Float64,          -- Humidity reading
    battery_level Float64,     -- Battery level
    alert_type String,         -- Alert type (HIGH_TEMPERATURE, HIGH_HUMIDITY, LOW_BATTERY)
    alert_time DateTime64(3)   -- Alert timestamp
)
ENGINE = MergeTree()
PARTITION BY toYYYYMMDD(alert_time)
ORDER BY (sensor_id, alert_time)
PRIMARY KEY (sensor_id)
SETTINGS index_granularity = 8192;

-- Create indexes for better performance
ALTER TABLE iot.sensor_raw_data ADD INDEX idx_sensor_id sensor_id TYPE bloom_filter(0.01) GRANULARITY 4;
ALTER TABLE iot.sensor_raw_data ADD INDEX idx_status status TYPE bloom_filter(0.01) GRANULARITY 4;
ALTER TABLE iot.sensor_raw_data ADD INDEX idx_temperature temperature TYPE minmax GRANULARITY 4;

ALTER TABLE iot.sensor_alerts ADD INDEX idx_sensor_id sensor_id TYPE bloom_filter(0.01) GRANULARITY 4;
ALTER TABLE iot.sensor_alerts ADD INDEX idx_alert_type alert_type TYPE bloom_filter(0.01) GRANULARITY 4;

