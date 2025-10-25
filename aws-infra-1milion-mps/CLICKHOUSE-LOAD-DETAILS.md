# ClickHouse Load - Detailed Documentation

## Overview
The `clickhouse-load` folder contains scripts and configurations for setting up ClickHouse database, creating schemas, and running low-rate data generation for testing and benchmarking.

## Purpose
- **Deploy** ClickHouse database schema for IoT sensor data
- **Load** test data at controlled rates for validation
- **Benchmark** query performance with realistic workloads
- **Validate** the complete data pipeline end-to-end

## Key Components

### 1. Schema Setup

#### 01-create-schema.sql
**Purpose:** Creates ClickHouse database and tables

**Tables Created:**

**a) benchmark.cpu_local**
- **Type:** Server CPU/memory metrics (TSBS schema)
- **Fields (30+):** hostname, region, datacenter, rack, os, arch, team, service, usage metrics, load averages, context switches, interrupts
- **Engine:** MergeTree
- **Partitioning:** By toYYYYMM(time) for efficient time-based queries
- **Sorting:** ORDER BY (hostname, time)
- **Materialized Column:** total_usage = usage_user + usage_system

**b) benchmark.sensors_local**
- **Type:** IoT device sensor readings
- **Fields (25+):** 
  - Device info: device_id, device_type, customer_id, site_id
  - Location: latitude, longitude, altitude
  - Timestamp: time (DateTime64(3) with millisecond precision)
  - Sensor readings: temperature, humidity, pressure, co2_level, noise_level, light_level, motion_detected
  - Device metrics: battery_level, signal_strength, memory_usage, cpu_usage
  - Status: status, error_count
  - Network: packets_sent, packets_received, bytes_sent, bytes_received
- **Engine:** ReplicatedMergeTree (for HA)
- **Partitioning:** By toYYYYMM(time)
- **Sorting:** ORDER BY (device_id, time)
- **Materialized Column:** has_alert = (temperature > 35 OR humidity > 80 OR battery_level < 20)
- **TTL:** 30 days data retention

**Schema Features:**
- **Compression:** Automatic compression for columnar storage
- **Indexing:** Primary key on device_id + time for fast lookups
- **Replication:** ReplicatedMergeTree for fault tolerance
- **Materialized columns:** Pre-computed derived fields

#### 00-create-schema-all-replicas.sh
**Purpose:** Deploys schema across all ClickHouse replica nodes

**What it does:**
1. Discovers all ClickHouse pods in the cluster
2. Executes schema SQL on each replica
3. Verifies table creation
4. Ensures consistency across all nodes

**Usage:**
```bash
./00-create-schema-all-replicas.sh
```

### 2. Data Generation

#### 02-low-rate-writer.py
**Purpose:** Continuous low-rate data writer for testing

**Configuration:**
- **Target Rate:** 25 records/second total (12.5 rec/sec per table)
- **Batch Size:** 5 records per batch
- **Tables:** Both cpu_local and sensors_local
- **Duration:** Runs continuously until stopped

**Data Generation Logic:**

**CPU Table:**
- Random hostnames from pool (server-001 to server-100)
- Realistic usage metrics (0-100%)
- Load averages (0-5.0)
- Context switches, interrupts
- Materialized total_usage computed by ClickHouse

**Sensors Table:**
- 100,000 unique device IDs (dev-0000000 to dev-0099999)
- 10,000 customers, 1,000 sites
- 20 device types (temperature_sensor, humidity_sensor, etc.)
- Realistic sensor ranges:
  - Temperature: 15-40°C
  - Humidity: 20-90%
  - Pressure: 980-1040 hPa
  - Battery: 10-100%
  - Signal strength: -90 to -30 dBm
- Status distribution (online, offline, maintenance, error)
- Automatic has_alert calculation by ClickHouse

**Rate Control:**
- Uses token bucket algorithm for precise rate limiting
- Smooth distribution over time
- Batch writes for efficiency

**Error Handling:**
- Automatic retry on connection failures
- Graceful handling of timeouts
- Logs all errors for debugging

### 3. Benchmarking

#### 03-low-rate-benchmark.py
**Purpose:** Query performance benchmark with realistic workloads

**Configuration:**
- **Target QPS:** 10 queries per second
- **Workers:** 2 concurrent threads
- **Duration:** Configurable (default: 300 seconds / 5 minutes)
- **Query Types:** 5 different analytical queries

**Query Types:**

**Q1: Recent Sensor Data**
```sql
SELECT * FROM benchmark.sensors_local 
ORDER BY time DESC 
LIMIT 100
```
Tests: Recent data retrieval, sorting performance

**Q2: Device Aggregation**
```sql
SELECT device_id, device_type, 
       avg(temperature) as avg_temp,
       avg(humidity) as avg_humidity,
       count(*) as record_count
FROM benchmark.sensors_local
WHERE time >= now() - INTERVAL 1 HOUR
GROUP BY device_id, device_type
ORDER BY record_count DESC
LIMIT 50
```
Tests: Time-range filtering, aggregation, grouping

**Q3: Alert Detection**
```sql
SELECT device_id, device_type,
       max(temperature) as max_temp,
       min(battery_level) as min_battery,
       count(*) as alert_count
FROM benchmark.sensors_local
WHERE has_alert = 1 
  AND time >= now() - INTERVAL 1 HOUR
GROUP BY device_id, device_type
ORDER BY alert_count DESC
```
Tests: Materialized column usage, conditional filtering

**Q4: Customer Analytics**
```sql
SELECT customer_id, site_id,
       count(DISTINCT device_id) as device_count,
       avg(temperature) as avg_temp,
       count(*) as total_readings
FROM benchmark.sensors_local
WHERE time >= now() - INTERVAL 24 HOUR
GROUP BY customer_id, site_id
ORDER BY total_readings DESC
LIMIT 100
```
Tests: Multi-level grouping, distinct counts

**Q5: Network Performance**
```sql
SELECT device_id,
       sum(packets_sent) as total_packets_sent,
       sum(packets_received) as total_packets_received,
       sum(bytes_sent) as total_bytes_sent,
       sum(bytes_received) as total_bytes_received
FROM benchmark.sensors_local
WHERE time >= now() - INTERVAL 1 HOUR
GROUP BY device_id
HAVING total_packets_sent > 1000
ORDER BY total_bytes_sent DESC
LIMIT 50
```
Tests: Sum aggregations, HAVING clause filtering

**Metrics Tracked:**
- Query latency (avg, p50, p95, p99)
- Success rate
- Errors per query type
- Throughput (QPS)
- Summary statistics

### 4. Deployment

#### 04-deployment.yaml
**Purpose:** Kubernetes manifests for automated deployment

**Resources Created:**

**a) ConfigMaps**
- `clickhouse-low-rate-scripts`: SQL schema files
- `clickhouse-low-rate-scripts-py`: Python scripts

**b) Job: Schema Creation**
```yaml
clickhouse-create-schema
```
- Runs once to create tables
- Uses Python + clickhouse-driver
- Waits for ClickHouse to be ready
- Idempotent (safe to re-run)

**c) Deployment: Data Writer**
```yaml
clickhouse-low-rate-writer
```
- Replicas: 1
- Resources: 200m CPU, 256Mi RAM
- Continuous data generation
- Auto-restart on failure

**d) Job: Benchmark (optional)**
```yaml
clickhouse-low-rate-benchmark
```
- Runs on-demand for testing
- Configurable duration and QPS
- Outputs detailed performance metrics

#### 05-deploy.sh
**Purpose:** Automated one-command deployment

**Steps:**
1. Creates ConfigMaps from SQL and Python files
2. Deploys schema creation job
3. Waits for schema job completion
4. Deploys data writer
5. Waits for writer to be ready
6. Shows status and logs
7. Displays verification commands

**Usage:**
```bash
chmod +x 05-deploy.sh
./05-deploy.sh
```

### 5. Setup and Maintenance

#### 00-install-clickhouse.sh
**Purpose:** Initial ClickHouse installation on Kubernetes

**What it installs:**
- ClickHouse Operator (for managing ClickHouse clusters)
- ClickHouse cluster with replication
- Service endpoints for client connections
- Monitoring integration (optional)

#### 00-nuclear-cleanup.sh
**Purpose:** Complete cleanup and reset

**What it does:**
- Drops all tables
- Deletes all data
- Removes persistent volumes
- Cleans up Kubernetes resources
- **WARNING:** Irreversible - use with caution

#### 99-cleanup-all.sh
**Purpose:** Remove test deployments but keep ClickHouse

**What it removes:**
- Data writer deployment
- Benchmark jobs
- ConfigMaps
- Leaves ClickHouse cluster and data intact

### 6. Monitoring and Setup Guides

#### setup-grafana-clickhouse.sh
**Purpose:** Configure Grafana dashboards for ClickHouse monitoring

**Sets up:**
- ClickHouse data source in Grafana
- Pre-built dashboards for:
  - Query performance metrics
  - Table sizes and growth
  - Ingestion rates
  - Alert counts
  - Device statistics

#### 00-SETUP-GUIDE.txt
**Purpose:** Step-by-step setup instructions

**Covers:**
- Prerequisites
- Installation order
- Configuration options
- Troubleshooting steps
- Best practices

#### NETWORK_PAYLOAD_ANALYSIS.txt
**Purpose:** Network and data payload analysis

**Contains:**
- Message size calculations
- Network bandwidth requirements
- Compression ratios
- Throughput estimates
- Optimization recommendations

## Data Flow

```
┌────────────────┐     ┌─────────────────┐     ┌──────────────────┐
│  Flink Output  │ ──→ │   ClickHouse    │ ←── │ Low-Rate Writer  │
│ (aggregated)   │     │ (sensors_local) │     │ (test data)      │
└────────────────┘     └─────────────────┘     └──────────────────┘
  ~500-1K/min            Columnar storage         25 records/sec
  Production data        Partitioned by time      Test/validation
                                ↓
                         ┌─────────────┐
                         │  Benchmark  │
                         │   Queries   │
                         └─────────────┘
                            10 QPS
```

## Performance Characteristics

### Write Performance
- **Low-rate writer:** 25 records/sec (for testing)
- **Flink pipeline:** 500-1,000 records/min (aggregated production data)
- **Batch size:** 5 records per batch (low-rate), 5,000 (Flink)
- **Latency:** <50ms per batch insert

### Query Performance
- **Simple queries:** <10ms (recent data, point lookups)
- **Aggregations:** <100ms (hourly aggregations)
- **Complex analytics:** <500ms (multi-table joins, large scans)
- **Materialized columns:** Near-instant filtering

### Storage
- **Compression:** 10x-20x typical compression ratio
- **Retention:** 30 days (configurable via TTL)
- **Partitioning:** Monthly partitions for efficient pruning
- **Replication:** 2-3 replicas for high availability

## Common Operations

### Verify Data Ingestion
```bash
kubectl exec -n clickhouse chi-iot-cluster-repl-iot-cluster-0-0-0 -- \
  clickhouse-client --query "SELECT count() FROM benchmark.sensors_local"
```

### View Recent Records
```bash
kubectl exec -n clickhouse chi-iot-cluster-repl-iot-cluster-0-0-0 -- \
  clickhouse-client --query "SELECT * FROM benchmark.sensors_local ORDER BY time DESC LIMIT 10"
```

### Check Table Sizes
```bash
kubectl exec -n clickhouse chi-iot-cluster-repl-iot-cluster-0-0-0 -- \
  clickhouse-client --query "SELECT table, formatReadableSize(sum(bytes)) as size FROM system.parts WHERE database='benchmark' GROUP BY table"
```

### Monitor Writer Logs
```bash
kubectl logs -f deployment/clickhouse-low-rate-writer
```

### Run Benchmark
```bash
kubectl delete job clickhouse-low-rate-benchmark --ignore-not-found=true
kubectl apply -f 04-deployment.yaml  # Only the benchmark job section
kubectl logs -f job/clickhouse-low-rate-benchmark
```

### Scale Writer (if needed)
```bash
kubectl scale deployment clickhouse-low-rate-writer --replicas=2
```

## Troubleshooting

### Writer Not Starting
**Check ClickHouse availability:**
```bash
kubectl get pods -n clickhouse
```

**Check ConfigMap:**
```bash
kubectl get configmap clickhouse-low-rate-scripts-py
```

**Check logs:**
```bash
kubectl logs deployment/clickhouse-low-rate-writer
```

### No Data in Tables
**Verify writer is running:**
```bash
kubectl get pods -l app=clickhouse-low-rate-writer
```

**Check connection:**
```bash
kubectl exec deployment/clickhouse-low-rate-writer -- \
  curl chi-iot-cluster-repl-iot-cluster-0-0-0.clickhouse.svc.cluster.local:8123
```

### Benchmark Failures
**Check table has data:**
```bash
kubectl exec -n clickhouse chi-iot-cluster-repl-iot-cluster-0-0-0 -- \
  clickhouse-client --query "SELECT count() FROM benchmark.sensors_local"
```

**View benchmark logs:**
```bash
kubectl logs job/clickhouse-low-rate-benchmark
```

## Dependencies
- **ClickHouse:** v22.x or later
- **Python:** 3.9+ with clickhouse-driver
- **Kubernetes:** For deployment
- **ClickHouse Operator:** For cluster management

## Summary
The clickhouse-load folder provides:
1. **Complete schema** for IoT sensor and CPU metrics
2. **Low-rate data generation** for testing and validation
3. **Query benchmarking** with realistic workloads
4. **Automated deployment** via Kubernetes
5. **Monitoring and verification** utilities
6. **Production-ready** table designs with optimization

