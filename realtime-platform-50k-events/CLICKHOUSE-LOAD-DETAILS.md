# ClickHouse Load - Detailed Documentation (50K Messages/Second)

## Overview
The `clickhouse-load` folder contains scripts and configurations for setting up ClickHouse database with cost-optimized t3 instances for moderate-scale analytics on **up to 50K messages/second** of input data.

## Purpose
- **Deploy** ClickHouse with EBS storage (cost-optimized)
- **Load** test data at controlled rates
- **Benchmark** query performance
- **Handle** ~800-1,000 inserts/minute from Flink (aggregated data)
- **Optimize** for cost (~$150/month vs ~$2,851/month for NVMe setup)

## Key Differences from 1M Setup

| Aspect | 50K Setup | 1M Setup |
|--------|-----------|----------|
| **Data Rate** | 800-1K inserts/min | 500-1K inserts/min |
| **Instance Type** | t3.xlarge | r6id.4xlarge |
| **vCPU** | 4 | 16 |
| **RAM** | 16 GB | 128 GB |
| **Storage** | EBS gp3 only | NVMe SSD + EBS |
| **Node Count** | 2-4 nodes | 6-12 nodes |
| **Storage per node** | 200 GB EBS | 950 GB NVMe + 100 GB EBS |
| **IOPS** | 3,000 (baseline) | 250K+ (NVMe) |
| **Monthly Cost** | ~$150 | ~$2,851 |
| **Query Latency** | <200ms | <100ms |

## Key Components

### 1. Schema Setup

#### 01-create-schema.sql
Creates the same tables as 1M setup:

**benchmark.sensors_local:**
- 25 fields for event/sensor data
- Engine: ReplicatedMergeTree
- Partitioning: Monthly (toYYYYMM)
- Sorting: ORDER BY (device_id, time)
- Materialized column: has_alert
- TTL: 30 days
- **Storage:** EBS gp3 (vs NVMe in 1M setup)

**benchmark.cpu_local:**
- 30+ fields for server metrics
- Same structure as 1M setup

**Cost Optimization:**
- **Replication:** 2 replicas (vs 3 in 1M)
- **Storage:** EBS gp3 only (no expensive NVMe)
- **Compression:** Aggressive (ZSTD level 3)

#### 00-create-schema-all-replicas.sh
Deploys schema across all ClickHouse replicas (2-4 nodes).

### 2. Data Generation

#### 02-low-rate-writer.py
**Purpose:** Continuous low-rate data writer for testing

**Same configuration as 1M:**
- Target Rate: 25 records/second
- Batch Size: 5 records
- Tables: sensors_local, cpu_local

**Use Case:** Validation and testing (not production load)

#### 03-low-rate-benchmark.py
**Purpose:** Query performance benchmark

**Configuration:**
- Target QPS: 10 queries/second
- Workers: 2 concurrent threads
- Query Types: 5 different analytical queries

**Expected Performance on t3.xlarge:**
- Simple queries: <20ms
- Aggregations: <200ms (vs <100ms on r6id.4xlarge)
- Complex analytics: <500ms (vs <200ms on r6id)

## Performance Characteristics

### Write Performance
- **From Flink:** 800-1,000 records/minute (aggregated)
- **Test writer:** 25 records/second
- **Batch size:** 1,000 records (from Flink)
- **Latency:** <100ms per batch

### Query Performance (t3.xlarge)
- **Simple queries:** <20ms (point lookups, recent data)
- **Aggregations:** <200ms (hourly aggregations)
- **Complex analytics:** <500ms (multi-table joins)
- **Materialized columns:** <10ms (using has_alert)

**Note:** Slightly slower than 1M setup due to:
- Less RAM for caching (16GB vs 128GB)
- EBS vs NVMe (3K IOPS vs 250K+ IOPS)
- Fewer CPU cores (4 vs 16)

### Storage
- **Compression:** 10-20x typical ratio
- **Retention:** 30 days (configurable)
- **Partitioning:** Monthly for efficient pruning
- **Replication:** 2 replicas (cost-optimized)
- **Volume Type:** EBS gp3 (3,000 baseline IOPS)

## Deployment Configuration

### Node Specification
```yaml
Instance: t3.xlarge
vCPU: 4
RAM: 16 GB
Storage: 200 GB EBS gp3 per node
Nodes: 2-4 (default: 2)
Total Capacity: 32-64 GB RAM, 8-16 cores
```

### 04-deployment.yaml
Same Kubernetes manifests as 1M setup:
- ConfigMaps for SQL and Python scripts
- Schema creation job
- Low-rate data writer
- Benchmark job (optional)

### 05-deploy.sh
One-command deployment script (same as 1M).

## Cost Analysis

### Per-Node Cost (t3.xlarge with EBS)

**Compute (t3.xlarge):**
- On-Demand: ~$152/month per node
- Spot: ~$60/month per node

**Storage (200 GB EBS gp3):**
- Cost: ~$16/month per node
- IOPS: 3,000 baseline (included)

**Total per node (Spot):** ~$76/month

### Cluster Cost Examples

**2-Node Cluster (Default):**
- Compute: ~$120/month (spot)
- Storage: ~$32/month
- **Total: ~$152/month**

**4-Node Cluster (High Availability):**
- Compute: ~$240/month (spot)
- Storage: ~$64/month
- **Total: ~$304/month**

**vs 1M Setup (6 nodes r6id.4xlarge):**
- Cost: ~$2,851/month
- **Savings: 90-95%** ($152 vs $2,851)

## Common Operations

### Verify Data Ingestion
```bash
kubectl exec -n clickhouse chi-iot-cluster-repl-iot-cluster-0-0-0 -- \
  clickhouse-client --query "SELECT count() FROM benchmark.sensors_local"
```

### Check Table Sizes
```bash
kubectl exec -n clickhouse chi-iot-cluster-repl-iot-cluster-0-0-0 -- \
  clickhouse-client --query "
    SELECT 
      table, 
      formatReadableSize(sum(bytes)) as size,
      sum(rows) as rows
    FROM system.parts 
    WHERE database='benchmark' 
    GROUP BY table"
```

### Monitor Resource Usage
```bash
# CPU and Memory
kubectl top pods -n clickhouse

# Storage usage
kubectl exec -n clickhouse chi-iot-cluster-repl-iot-cluster-0-0-0 -- \
  df -h | grep clickhouse
```

### Run Benchmark
```bash
cd clickhouse-load

# Run query benchmark (10 QPS, 5 query types)
kubectl apply -f 04-deployment.yaml  # Benchmark job section
kubectl logs -f job/clickhouse-low-rate-benchmark
```

## Query Optimization for t3.xlarge

### Best Practices
1. **Use materialized columns** (pre-computed, near-instant)
2. **Limit time ranges** (use last 1 hour vs last 7 days)
3. **Use primary key** in WHERE clause when possible
4. **Avoid SELECT \*** (use specific columns)
5. **Use PREWHERE** for filtering before aggregation

### Example Optimized Query
```sql
-- Fast: Uses materialized column and primary key
SELECT device_id, avg(temperature), count(*) as cnt
FROM benchmark.sensors_local
WHERE device_id LIKE 'sensor_1%'  -- Uses primary key
  AND has_alert = 1                -- Uses materialized column
  AND time >= now() - INTERVAL 1 HOUR  -- Limited time range
GROUP BY device_id
ORDER BY cnt DESC
LIMIT 100
```

### Query Performance Tips
- **Warm cache:** Run query twice, second run will be faster
- **Sampling:** Use SAMPLE 0.1 for approximate results on large datasets
- **Partitioning:** Query pruning works best with monthly partitions

## Monitoring

### Storage Usage
```bash
kubectl exec -n clickhouse chi-iot-cluster-repl-iot-cluster-0-0-0 -- \
  clickhouse-client --query "
    SELECT 
      formatReadableSize(sum(bytes)) as total_size,
      formatReadableSize(sum(bytes_on_disk)) as compressed_size,
      round(sum(bytes) / sum(bytes_on_disk), 2) as compression_ratio
    FROM system.parts
    WHERE database = 'benchmark'"
```

### Query Statistics
```bash
kubectl exec -n clickhouse chi-iot-cluster-repl-iot-cluster-0-0-0 -- \
  clickhouse-client --query "
    SELECT 
      query_duration_ms,
      read_rows,
      read_bytes,
      query
    FROM system.query_log
    WHERE type = 'QueryFinish'
    ORDER BY event_time DESC
    LIMIT 10"
```

## Deployment Steps

### 1. Install ClickHouse
```bash
cd clickhouse-load
./00-install-clickhouse.sh
```

Creates ClickHouse cluster with t3.xlarge nodes and EBS storage

### 2. Create Schema
```bash
./00-create-schema-all-replicas.sh
```

Creates tables on all 2-4 replicas

### 3. Deploy Test Writer (Optional)
```bash
./05-deploy.sh
```

Starts low-rate writer for validation

### 4. Verify
```bash
kubectl get pods -n clickhouse
kubectl exec -n clickhouse chi-iot-cluster-repl-iot-cluster-0-0-0 -- \
  clickhouse-client --query "SELECT count() FROM benchmark.sensors_local"
```

## Troubleshooting

### Slow Queries

**Check if data is in memory cache:**
```bash
kubectl exec -n clickhouse chi-iot-cluster-repl-iot-cluster-0-0-0 -- \
  clickhouse-client --query "SYSTEM DROP MARK CACHE"
```

**Check query plan:**
```bash
kubectl exec -n clickhouse chi-iot-cluster-repl-iot-cluster-0-0-0 -- \
  clickhouse-client --query "EXPLAIN SELECT ... FROM ..."
```

**Solution:**
- Add more RAM by upgrading to t3.2xlarge
- Reduce query time range
- Add more replicas for parallel processing

### Out of Memory
**Check memory usage:**
```bash
kubectl top pods -n clickhouse
```

**Solution:**
- Upgrade to t3.2xlarge (32 GB RAM)
- Reduce data retention period
- Enable more aggressive TTL

### Storage Full
**Check disk usage:**
```bash
kubectl exec -n clickhouse chi-iot-cluster-repl-iot-cluster-0-0-0 -- \
  df -h | grep clickhouse
```

**Solution:**
- Increase EBS volume size (via Terraform)
- Reduce TTL from 30 to 14 days
- Enable more aggressive compression

## Upgrade Path

### To Handle More Data

**Scale horizontally (add nodes):**
```bash
# Update terraform.tfvars
clickhouse_desired_size = 4

# Apply
terraform apply
```

**Scale vertically (larger instances):**
```bash
# Upgrade to t3.2xlarge (8 vCPU, 32 GB RAM)
# Update main.tf instance type
# Cost: ~$120/month per node (spot)
```

### To 1M Setup

For higher performance needs:
1. Upgrade to r6id.4xlarge (16 vCPU, 128 GB RAM, NVMe)
2. Add NVMe storage mounts
3. Increase node count to 6-12
4. Cost increases to ~$2,851/month
5. Query performance: <100ms (vs <200ms)

## Summary

The clickhouse-load folder for 50K setup provides:

1. **Cost-optimized ClickHouse deployment** with t3.xlarge and EBS
2. **Same schema** as 1M setup (benchmark.sensors_local)
3. **Moderate query performance** (<200ms vs <100ms)
4. **90% cost savings** (~$150 vs ~$2,851/month)
5. **Scalable storage** with EBS gp3
6. **Production-ready** with replication and TTL
7. **Easy upgrade path** to high-performance setup

**Perfect for:**
- Development and testing environments
- Small to medium production workloads
- Budget-conscious deployments
- Analytics with moderate query loads
- Growing platforms planning to scale

