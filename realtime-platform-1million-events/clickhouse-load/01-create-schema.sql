-- ClickHouse Schema for Flink Benchmark - Matching latest-0 Schema
-- Compatible with TSBS-style benchmarking, non-clustered deployment

-- Create database
CREATE DATABASE IF NOT EXISTS benchmark;

-- ============================================
-- CPU METRICS TABLE (Server monitoring)
-- Matching latest-0 schema with full field set
-- ============================================
CREATE TABLE IF NOT EXISTS benchmark.cpu_local
(
    -- Tags (cardinality in parentheses)
    hostname String,            -- (10,000 hosts)
    region String,              -- (10 regions)
    datacenter String,          -- (50 datacenters)
    rack String,                -- (500 racks)
    os String,                  -- (5 OS types)
    arch String,                -- (3 architectures)
    team String,                -- (100 teams)
    service String,             -- (500 services)
    service_version String,     -- (5 versions per service)
    service_environment String, -- (4 environments)
    
    -- Timestamp with millisecond precision
    time DateTime64(3),
    
    -- Core CPU metrics
    usage_user Float32,
    usage_system Float32,
    usage_idle Float32,
    usage_nice Float32,
    usage_iowait Float32,
    usage_irq Float32,
    usage_softirq Float32,
    usage_steal Float32,
    usage_guest Float32,
    usage_guest_nice Float32,
    
    -- Load averages
    load1 Float32,
    load5 Float32,
    load15 Float32,
    
    -- System info
    n_cpus UInt16,
    n_users UInt16,
    n_processes UInt32,
    uptime_seconds UInt64,
    
    -- Additional metrics for realistic load
    context_switches UInt64,
    interrupts UInt64,
    software_interrupts UInt64,
    
    -- Calculated field for hot path queries
    total_usage Float32 MATERIALIZED (usage_user + usage_system),
    
    -- INDEXES INLINE (prevents ZooKeeper metadata mismatch in ReplicatedMergeTree)
    INDEX idx_hostname hostname TYPE bloom_filter(0.01) GRANULARITY 4,
    INDEX idx_service service TYPE bloom_filter(0.01) GRANULARITY 4,
    INDEX idx_cpu_usage total_usage TYPE minmax GRANULARITY 4
)
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/benchmark.cpu_local', '{replica}')
PARTITION BY toYYYYMM(time)
PRIMARY KEY (service, hostname, toStartOfHour(time))
ORDER BY (service, hostname, toStartOfHour(time), time)
TTL toDateTime(time) + INTERVAL 90 DAY DELETE
SETTINGS 
    index_granularity = 8192;

-- ============================================
-- CPU DISTRIBUTED TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS benchmark.cpu_distributed AS benchmark.cpu_local
ENGINE = Distributed('iot-cluster', 'benchmark', 'cpu_local', rand());

-- ============================================
-- IOT SENSORS TABLE
-- Matching latest-0 schema with full field set
-- ============================================
CREATE TABLE IF NOT EXISTS benchmark.sensors_local
(
    -- Device identifiers (optimized for integer-based data)
    device_id String,           -- (100,000 devices) - converted from sensor_id
    device_type String,         -- (20 types) - converted from sensor_type
    customer_id String,         -- (10,000 customers) - default mapping
    site_id String,             -- (1,000 sites) - converted from location
    
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
    has_alert UInt8 MATERIALIZED (temperature > 35 OR humidity > 80 OR battery_level < 20),
    
    -- INDEXES INLINE (prevents ZooKeeper metadata mismatch in ReplicatedMergeTree)
    INDEX idx_device_id device_id TYPE bloom_filter(0.01) GRANULARITY 4,
    INDEX idx_customer customer_id TYPE bloom_filter(0.01) GRANULARITY 4,
    INDEX idx_temperature temperature TYPE minmax GRANULARITY 4,
    INDEX idx_status status TYPE bloom_filter(0.01) GRANULARITY 4
)
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/benchmark.sensors_local', '{replica}')
PARTITION BY toYYYYMMDD(time)
PRIMARY KEY (device_id, time)
ORDER BY (device_id, time)
TTL toDateTime(time) + INTERVAL 30 DAY DELETE
SETTINGS 
    index_granularity = 8192;

-- ============================================
-- DISTRIBUTED TABLE (for writes and queries across all shards)
-- ============================================
CREATE TABLE IF NOT EXISTS benchmark.sensors_distributed AS benchmark.sensors_local
ENGINE = Distributed('iot-cluster', 'benchmark', 'sensors_local', rand());

-- ============================================
-- INDEXES
-- ============================================
-- Note: Indexes are now defined inline in the CREATE TABLE statements above
-- This prevents ZooKeeper metadata mismatch errors in ReplicatedMergeTree tables

