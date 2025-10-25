# Flink Performance Fixes - 2K → 30K msgs/sec

## 🔴 Problems Identified

Your Flink setup was only processing **2K msgs/sec** when producing at **30K msgs/sec** due to:

### 1. **Parallelism Bottleneck** ⚠️ CRITICAL
- **Issue**: Java code hardcoded `env.setParallelism(1)` - only 1 task processing ALL messages
- **Impact**: Single-threaded processing despite having 4 available task slots
- **Fix**: Removed hardcoded parallelism, increased YAML config from 2 → 8

### 2. **Small Batch Size**
- **Issue**: Batch size = 100 records (way too small for 30K msgs/sec)
- **Impact**: ~20 database operations/second = high overhead
- **Fix**: Increased to 1000 records per batch (10x improvement)

### 3. **Insufficient Resources**
- **Issue**: Only 2 TaskManagers with 0.8 CPU each = 1.6 total CPU
- **Impact**: Not enough compute power for 30K msgs/sec
- **Fix**: 
  - 4 TaskManagers (up from 2)
  - 1.0 CPU per TaskManager (up from 0.8)
  - 2048MB RAM per TaskManager (up from 1536MB)
  - 4 task slots per TaskManager (up from 2)
  - **Total parallelism: 16 slots (4 × 4)**

### 4. **Slow Consumer Polling**
- **Issue**: 5-second Pulsar receive timeout
- **Impact**: Wasted time waiting for messages
- **Fix**: Reduced to 1 second + added 10K message buffer

### 5. **ClickHouse Transaction Warnings** ⚠️
- **Issue**: Code using `commit()`/`rollback()` but ClickHouse doesn't support transactions
- **Impact**: Warning spam + unnecessary overhead
- **Fix**: Removed all transaction code, added `jdbcCompliant=false` parameter

---

## ✅ Changes Applied

### Java Code Changes (`JDBCFlinkConsumer.java`)

```java
// 1. REMOVED hardcoded parallelism
- env.setParallelism(1);
+ // Use parallelism from FlinkDeployment YAML

// 2. INCREASED batch size
- private static final int BATCH_SIZE = 100;
+ private static final int BATCH_SIZE = 1000;

// 3. OPTIMIZED Pulsar consumer
consumer = client.newConsumer()
    .ackTimeout(60, TimeUnit.SECONDS)     // Increased for checkpoint-based acks
+   .receiverQueueSize(10000)             // NEW: Buffer 10K messages
    .subscribe();

// 4. FASTER polling
- Message<byte[]> message = consumer.receive(5, TimeUnit.SECONDS);
+ Message<byte[]> message = consumer.receive(1, TimeUnit.SECONDS);

// 5. FIXED ClickHouse transaction warnings
+ String finalUrl = jdbcUrl + "?jdbcCompliant=false";
connection = DriverManager.getConnection(finalUrl);
- connection.setAutoCommit(false);        // REMOVED
- connection.commit();                     // REMOVED (all instances)
- connection.rollback();                   // REMOVED
```

### YAML Config Changes (`flink-job-deployment.yaml`)

```yaml
flinkConfiguration:
  taskmanager.numberOfTaskSlots: "4"      # Was: 2 → Now: 4

taskManager:
  replicas: 4                              # Was: 2 → Now: 4
  resource:
    memory: "2048m"                        # Was: 1536m → Now: 2048m
    cpu: 1.0                               # Was: 0.8 → Now: 1.0

job:
  parallelism: 8                           # Was: 2 → Now: 8
```

**Total Available Parallelism**: 4 TaskManagers × 4 slots = **16 parallel tasks**  
**Job Parallelism Used**: **8 tasks** (leaves room for scaling)

---

## 🚀 Deployment Instructions

### Step 1: Rebuild Docker Image with Updated Code
```bash
cd /Users/vijayabhaskarv/IOT/datapipeline-0/Flink-Benchmark/low_infra_flink/flink-load

# Build and push new image
./build-and-push.sh
```

### Step 2: Delete Existing Flink Job
```bash
kubectl delete flinkdeployment iot-flink-job -n flink-benchmark

# Verify deletion
kubectl get flinkdeployment -n flink-benchmark
```

### Step 3: Deploy Updated Configuration
```bash
kubectl apply -f flink-job-deployment.yaml -n flink-benchmark
```

### Step 4: Monitor Deployment
```bash
# Watch deployment status
kubectl get flinkdeployment iot-flink-job -n flink-benchmark -w

# Check TaskManager pods
kubectl get pods -n flink-benchmark -l app=iot-flink-job

# Expected: 4 TaskManager pods + 1 JobManager pod
```

### Step 5: Verify Throughput
```bash
# Check Flink logs for throughput
kubectl logs -n flink-benchmark -l app=iot-flink-job -c flink-main-container --tail=100

# Look for:
# - "✅ Batch executed: 1000 records" (should happen frequently)
# - No transaction warnings
# - Processing messages from multiple parallel tasks

# Check metrics in Flink UI
kubectl port-forward -n flink-benchmark svc/iot-flink-job-rest 8081:8081
# Open: http://localhost:8081
```

---

## 📊 Expected Performance Improvement

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| **Parallelism** | 1 task | 8 tasks | **8x** |
| **Batch Size** | 100 records | 1000 records | **10x** |
| **TaskManagers** | 2 pods | 4 pods | **2x** |
| **Total CPU** | 1.6 cores | 4.0 cores | **2.5x** |
| **Task Slots** | 4 total | 16 total | **4x** |
| **Consumer Buffer** | Default | 10K messages | **Better buffering** |
| **Polling Timeout** | 5s | 1s | **5x faster** |
| **Expected Throughput** | 2K msgs/sec | **15-25K msgs/sec** | **~10x** |

---

## 🎯 Performance Tuning Tips

### If Still Not Reaching 30K msgs/sec:

#### 1. **Check Pulsar Topic Partitions**
```bash
# Pulsar topics should be partitioned for parallel consumption
kubectl exec -n pulsar pulsar-proxy-0 -- bin/pulsar-admin topics partitioned-lookup persistent://public/default/iot-sensor-data

# If not partitioned, create partitioned topic:
kubectl exec -n pulsar pulsar-proxy-0 -- bin/pulsar-admin topics create-partitioned-topic persistent://public/default/iot-sensor-data --partitions 8
```

#### 2. **Increase Parallelism Further** (if CPU allows)
```yaml
# In flink-job-deployment.yaml
job:
  parallelism: 12  # Use 12 out of 16 available slots
```

#### 3. **Add More TaskManagers** (if budget allows)
```yaml
taskManager:
  replicas: 6  # 6 × 4 slots = 24 total parallelism
```

#### 4. **Monitor ClickHouse Write Performance**
```bash
# Check if ClickHouse is the bottleneck
kubectl exec -n clickhouse clickhouse-iot-cluster-repl-0-0-0 -- clickhouse-client --query "SELECT * FROM system.metrics WHERE metric LIKE '%Insert%'"

# If ClickHouse is slow, consider:
# - Batch async inserts
# - Increase ClickHouse resources
# - Use distributed tables
```

#### 5. **Optimize Checkpoint Interval**
```yaml
# In flink-job-deployment.yaml, reduce checkpoint frequency
flinkConfiguration:
  execution.checkpointing.interval: "120s"  # Change from 60s → 120s
```

#### 6. **Monitor Backpressure**
```bash
# Open Flink UI and check for backpressure
kubectl port-forward -n flink-benchmark svc/iot-flink-job-rest 8081:8081
# Navigate to: Running Jobs → Click Job → Look for red backpressure indicators
```

---

## 🔍 Troubleshooting

### Issue: Job Fails to Start
```bash
# Check logs
kubectl logs -n flink-benchmark iot-flink-job-jobmanager-0

# Common causes:
# - Insufficient CPU/memory on nodes
# - Image pull errors (check ECR permissions)
# - Invalid JDBC URL
```

### Issue: Still Seeing Transaction Warnings
```bash
# Verify jdbcCompliant=false is applied
kubectl logs -n flink-benchmark -l app=iot-flink-job | grep "jdbcCompliant"

# If not, rebuild Docker image (Step 1 above)
```

### Issue: Low Throughput Despite Changes
```bash
# 1. Check if all TaskManagers are running
kubectl get pods -n flink-benchmark | grep taskmanager

# 2. Check Pulsar consumer lag
kubectl exec -n pulsar pulsar-proxy-0 -- bin/pulsar-admin topics stats persistent://public/default/iot-sensor-data

# 3. Check ClickHouse CPU/memory usage
kubectl top pods -n clickhouse

# 4. Verify parallelism in Flink UI
# Should see 8 parallel tasks running
```

---

## 📈 Monitoring Commands

```bash
# Watch Flink job status
kubectl get flinkdeployment -n flink-benchmark -w

# Monitor pod resource usage
kubectl top pods -n flink-benchmark

# Check application logs
kubectl logs -n flink-benchmark -l app=iot-flink-job -f

# Access Flink Web UI
kubectl port-forward -n flink-benchmark svc/iot-flink-job-rest 8081:8081

# Query ClickHouse for ingestion rate
kubectl exec -n clickhouse clickhouse-iot-cluster-repl-0-0-0 -- clickhouse-client --query "
SELECT 
    count() as records_inserted,
    round(count() / 60, 2) as records_per_second
FROM benchmark.sensors_local
WHERE time >= now() - INTERVAL 1 MINUTE
"
```

---

## 📝 Summary

These changes address all identified bottlenecks:
- ✅ **Parallelism**: 1 → 8 tasks (8x more processing power)
- ✅ **Batch Size**: 100 → 1000 records (10x fewer DB ops)
- ✅ **Resources**: 2x more TaskManagers, 25% more CPU per pod
- ✅ **Consumer**: 10K message buffer + faster polling
- ✅ **ClickHouse**: No more transaction warnings

**Expected Result**: **15-25K msgs/sec** throughput (vs 2K before)

To reach 30K msgs/sec, consider partitioning Pulsar topics and increasing parallelism to 12-16 tasks.

