# Flink 1-Minute Aggregation Guide

## 🎯 Overview

**Problem**: Writing 30K individual sensor messages per second to ClickHouse = **1.8 billion writes per day**

**Solution**: Aggregate sensor data in 1-minute windows **before** writing to ClickHouse

**Result**: **30K msgs/sec → ~500-1000 aggregated records/minute** = **99.9% reduction in writes!**

---

## 📊 What Changed

### Before (Raw Messages)
```
Pulsar (30K msgs/sec) → Flink → ClickHouse (30K inserts/sec)
├─ Device A: msg1, msg2, msg3... (1800 msgs/min)
├─ Device B: msg1, msg2, msg3... (1800 msgs/min)
└─ Device C: msg1, msg2, msg3... (1800 msgs/min)
```

### After (1-Minute Aggregation)
```
Pulsar (30K msgs/sec) → Flink Aggregation → ClickHouse (~500 inserts/min)
├─ Device A: [1min avg] (1 aggregated record)
├─ Device B: [1min avg] (1 aggregated record)
└─ Device C: [1min avg] (1 aggregated record)
```

---

## 🔧 Implementation Details

### 1. **Windowing Strategy**
- **Window Type**: Tumbling (non-overlapping)
- **Window Size**: 1 minute
- **Key**: `device_id` (each device aggregated separately)
- **Time**: Processing time (uses system clock)

### 2. **Aggregation Logic**

For each 1-minute window per device:

| Field Type | Aggregation Method | Example |
|------------|-------------------|---------|
| **Metadata** | First value | device_id, device_type, customer_id, site_id |
| **Location** | First value | latitude, longitude, altitude |
| **Sensor Readings** | **Average** | temperature, humidity, pressure, CO2, noise, light |
| **Battery/Signal** | **Average** | battery_level, signal_strength |
| **Motion** | Majority vote (>50%) | motion_detected |
| **Status** | Average | status code |
| **Errors** | **Sum** | error_count |
| **Network** | **Sum** | packets_sent, packets_received, bytes_sent, bytes_received |

### 3. **Example Aggregation**

**Input (60 messages over 1 minute for Device_001):**
```json
{ "device_id": "sensor_001", "temperature": 22.5, "humidity": 45.0, "battery": 85.0 }
{ "device_id": "sensor_001", "temperature": 23.0, "humidity": 46.0, "battery": 84.8 }
{ "device_id": "sensor_001", "temperature": 22.8, "humidity": 45.5, "battery": 84.6 }
... (57 more messages)
```

**Output (1 aggregated record):**
```json
{
  "device_id": "sensor_001",
  "temperature": 22.77,      // Average of 60 readings
  "humidity": 45.50,         // Average of 60 readings
  "battery_level": 84.20,    // Average of 60 readings
  "packets_sent": 3600,      // Sum of all packets
  "error_count": 2           // Sum of errors
}
```

---

## 📈 Performance Impact

### Write Reduction Calculation

Assuming:
- **30,000 msgs/sec** incoming rate
- **500 unique devices** sending data

**Before Aggregation:**
- ClickHouse writes: **30,000/sec** = **1,800,000/minute** = **2.6 billion/day**

**After 1-Minute Aggregation:**
- ClickHouse writes: **500 devices × 1 record/min** = **500/minute** = **720,000/day**
- **Reduction**: **99.97%** fewer writes!

### Throughput Impact

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| **ClickHouse Writes/sec** | 30,000 | 8 | **99.97% reduction** |
| **ClickHouse Writes/min** | 1,800,000 | 500 | **99.97% reduction** |
| **ClickHouse Writes/day** | 2.6 billion | 720K | **99.97% reduction** |
| **Flink Memory Usage** | Low | Medium | Small state per device |
| **Data Latency** | Real-time | 1-minute | Acceptable for analytics |
| **Storage Requirements** | High | Very Low | **99.97% reduction** |

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Pulsar Topic: iot-sensor-data                              │
│  30,000 messages/second                                      │
└─────────────┬───────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────────┐
│  Flink Source (Pulsar Consumer)                             │
│  - Checkpoint-aware                                          │
│  - Shared subscription (parallel consumption)                │
└─────────────┬───────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────────┐
│  Parse JSON → SensorRecord                                   │
│  Extract device_id, sensor readings                          │
└─────────────┬───────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────────┐
│  Key By: device_id                                           │
│  Parallelism: 8 tasks                                        │
└─────────────┬───────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────────┐
│  1-Minute Tumbling Window                                    │
│  Per Device Aggregation:                                     │
│  - Count: number of messages                                 │
│  - Avg: temperature, humidity, pressure, CO2, etc.           │
│  - Sum: packets, bytes, errors                               │
│  - Min/Max: tracked but not written (can be added)           │
└─────────────┬───────────────────────────────────────────────┘
              │
              ▼ Every 1 minute per device
┌─────────────────────────────────────────────────────────────┐
│  ClickHouse JDBC Sink                                        │
│  - Batch size: 1000 aggregated records                       │
│  - Write: ~500 records/minute = ~8 records/second            │
│  - Table: benchmark.sensors_local                            │
└─────────────────────────────────────────────────────────────┘
```

---

## 💾 ClickHouse Schema

The aggregated data fits the same schema as raw data:

```sql
CREATE TABLE benchmark.sensors_local (
    device_id String,
    device_type String,
    customer_id String,
    site_id String,
    latitude Float64,
    longitude Float64,
    altitude Float64,
    time DateTime DEFAULT now(),
    
    -- Aggregated sensor readings (averages)
    temperature Float64,
    humidity Float64,
    pressure Float64,
    co2_level Float64,
    noise_level Float64,
    light_level Float64,
    motion_detected UInt8,
    
    -- Aggregated device metrics (averages)
    battery_level Float64,
    signal_strength Float64,
    memory_usage Float64,
    cpu_usage Float64,
    
    -- Status
    status UInt8,
    error_count Int32,  -- Sum of errors in 1-minute window
    
    -- Network metrics (sums)
    packets_sent UInt64,
    packets_received UInt64,
    bytes_sent UInt64,
    bytes_received UInt64
) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/sensors_local', '{replica}')
ORDER BY (device_id, time);
```

**Note**: The `time` field is set to `now()` when the aggregated record is written, representing the end of the 1-minute window.

---

## 🔍 Monitoring & Verification

### 1. Check Aggregation in Flink Logs
```bash
kubectl logs -n flink-benchmark -l app=iot-flink-job --tail=100 | grep "Aggregated window"

# Expected output every minute:
# ✅ Aggregated window: device=sensor_001, count=1800 records, avg_temp=22.5
# ✅ Aggregated window: device=sensor_002, count=1850 records, avg_temp=23.1
```

### 2. Verify Reduced Write Rate
```bash
# Check ClickHouse insertion rate (should be ~500/min instead of 30K/sec)
kubectl exec -n clickhouse clickhouse-iot-cluster-repl-0-0-0 -- clickhouse-client --query "
SELECT 
    countMerge(records) as total_records,
    countMerge(records) / 60 as records_per_second
FROM (
    SELECT count() as records
    FROM benchmark.sensors_local
    WHERE time >= now() - INTERVAL 1 MINUTE
)
"
```

### 3. Verify Data Quality
```bash
# Check average temperature for a specific device over last hour
kubectl exec -n clickhouse clickhouse-iot-cluster-repl-0-0-0 -- clickhouse-client --query "
SELECT 
    device_id,
    count() as aggregated_records,
    avg(temperature) as avg_temp,
    avg(humidity) as avg_humidity,
    sum(error_count) as total_errors
FROM benchmark.sensors_local
WHERE device_id = 'sensor_001'
  AND time >= now() - INTERVAL 1 HOUR
GROUP BY device_id
"

# Expected: 60 aggregated records (1 per minute) for the last hour
```

### 4. Monitor Flink State Size
```bash
# Access Flink Web UI
kubectl port-forward -n flink-benchmark svc/iot-flink-job-rest 8081:8081

# Navigate to: Running Jobs → Click Job → State
# Check: State size per window (should be reasonable, ~few KB per device)
```

---

## ⚙️ Configuration Options

### Adjust Window Size

**Change aggregation window from 1 minute to 5 minutes:**

```java
// In JDBCFlinkConsumer.java, line 80
.window(TumblingProcessingTimeWindows.of(Time.minutes(5)))  // Changed from 1 to 5
```

**Impact:**
- 1 minute: More frequent writes, fresher data
- 5 minutes: Fewer writes, higher aggregation
- 1 hour: Minimal writes, maximum aggregation

### Add Min/Max Tracking

Currently we track min/max in the accumulator but don't write them. To add:

1. **Modify ClickHouse schema**:
```sql
ALTER TABLE benchmark.sensors_local ADD COLUMN temp_min Float64;
ALTER TABLE benchmark.sensors_local ADD COLUMN temp_max Float64;
```

2. **Update Sink** to write min/max values (currently only writing averages)

### Change Aggregation Key

**Aggregate by site instead of device:**

```java
// In JDBCFlinkConsumer.java, line 79
.keyBy(record -> record.site_id)  // Changed from device_id to site_id
```

---

## 🚀 Deployment

### Step 1: Rebuild Docker Image
```bash
cd /Users/vijayabhaskarv/IOT/datapipeline-0/Flink-Benchmark/low_infra_flink/flink-load
./build-and-push.sh
```

### Step 2: Delete Old Flink Job
```bash
kubectl delete flinkdeployment iot-flink-job -n flink-benchmark
```

### Step 3: Deploy New Aggregated Job
```bash
kubectl apply -f flink-job-deployment.yaml -n flink-benchmark
```

### Step 4: Verify Aggregation is Working
```bash
# Wait ~2 minutes, then check logs
kubectl logs -n flink-benchmark -l app=iot-flink-job --tail=50 | grep "Aggregated"

# Should see output like:
# ✅ Aggregated window: device=sensor_001, count=1800 records, avg_temp=22.5
```

---

## 📊 Analytics Queries

With aggregated data, queries are still powerful:

### Average Temperature Per Device (Last Hour)
```sql
SELECT 
    device_id,
    avg(temperature) as avg_temp,
    count() as data_points
FROM benchmark.sensors_local
WHERE time >= now() - INTERVAL 1 HOUR
GROUP BY device_id
ORDER BY avg_temp DESC
LIMIT 10;
```

### Devices with Battery Issues
```sql
SELECT 
    device_id,
    avg(battery_level) as avg_battery
FROM benchmark.sensors_local
WHERE time >= now() - INTERVAL 1 DAY
GROUP BY device_id
HAVING avg_battery < 20
ORDER BY avg_battery ASC;
```

### Total Errors Per Customer
```sql
SELECT 
    customer_id,
    sum(error_count) as total_errors
FROM benchmark.sensors_local
WHERE time >= now() - INTERVAL 1 DAY
GROUP BY customer_id
ORDER BY total_errors DESC;
```

---

## 🎛️ Trade-offs

### Advantages ✅
- **99.97% fewer database writes** → Massive cost savings
- **Lower ClickHouse CPU/memory** usage
- **Better compression** in ClickHouse (fewer rows)
- **Faster analytical queries** (less data to scan)
- **Reduced network traffic** to ClickHouse

### Disadvantages ⚠️
- **1-minute data latency** (vs real-time)
- **Loss of individual message details** (only averages stored)
- **Slightly more Flink state** (small impact)
- **Can't query individual sensor readings** (only aggregates)

### When to Use Aggregation?
- ✅ **Analytics use cases** (dashboards, trends, reports)
- ✅ **Historical data** (long-term storage)
- ✅ **High-volume sensors** (IoT, metrics, logs)
- ✅ **Cost optimization** scenarios

### When NOT to Use Aggregation?
- ❌ **Need individual message details** (debugging, audit trails)
- ❌ **Real-time alerting** on specific values
- ❌ **ML training** requiring raw data points
- ❌ **Compliance** requiring full data retention

---

## 💡 Hybrid Approach (Best of Both Worlds)

You can run **two Flink jobs** in parallel:

1. **Raw Data Job**: Write last 24 hours to `sensors_local_raw` (for debugging)
2. **Aggregated Job**: Write aggregated data to `sensors_local` (for analytics)

```yaml
# Deploy both jobs
kubectl apply -f flink-job-deployment-raw.yaml
kubectl apply -f flink-job-deployment-aggregated.yaml
```

**Benefits:**
- Keep raw data for 24 hours (debugging, alerts)
- Aggregated data for long-term analytics
- Use ClickHouse TTL to auto-delete old raw data

---

## 🔗 Related Files

- **Java Code**: `flink-consumer/src/main/java/com/iot/pipeline/flink/JDBCFlinkConsumer.java`
- **Deployment**: `flink-job-deployment.yaml`
- **Performance Fixes**: `PERFORMANCE-FIXES.md`
- **Quick Reference**: `QUICK-FIX-SUMMARY.md`

---

## 📝 Summary

**Aggregation reduces ClickHouse writes from 30K/sec to 8/sec (99.97% reduction) while preserving analytical capabilities.**

With 1-minute windows:
- **Input**: 1.8M messages/minute
- **Output**: 500 aggregated records/minute
- **Latency**: 1-minute delay
- **Data Loss**: Individual readings → Averages only

This is perfect for IoT analytics where trends matter more than individual data points! 🚀

