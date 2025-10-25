# Flink State Management Guide - Windowed Aggregation

## 🗄️ Overview

**Yes, windowed aggregation values are stored in Flink's state backend!**

During the 1-minute window period, all partial aggregation results (sums, mins, maxs, counts) are maintained in **RocksDB state** and periodically checkpointed to **S3** for fault tolerance.

---

## 📊 What Gets Stored in State

### Per Device, Per Window:

```java
Accumulator State (per device_id, per 1-minute window):
├── Metadata (captured from first message)
│   ├── device_id: String
│   ├── device_type: String
│   ├── customer_id: String
│   ├── site_id: String
│   ├── latitude: double
│   ├── longitude: double
│   └── altitude: double
│
├── Counters
│   ├── count: long (# of messages in window)
│   ├── motion_detected_count: int
│   ├── error_count_sum: int
│   └── status_sum: int
│
├── Sensor Readings (for each metric: sum, min, max)
│   ├── Temperature: temp_sum, temp_min, temp_max
│   ├── Humidity: hum_sum, hum_min, hum_max
│   ├── Pressure: press_sum, press_min, press_max
│   ├── CO2: co2_sum, co2_min, co2_max
│   ├── Noise: noise_sum, noise_min, noise_max
│   ├── Light: light_sum, light_min, light_max
│   ├── Battery: battery_sum, battery_min, battery_max
│   └── Signal: signal_sum, signal_min, signal_max
│
└── Network Metrics
    ├── packets_sent_sum: long
    ├── packets_received_sum: long
    ├── bytes_sent_sum: long
    └── bytes_received_sum: long

Total per device window: ~500-800 bytes
```

---

## 🏗️ State Backend Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Flink TaskManager (In-Memory + RocksDB)                    │
│                                                              │
│  ┌──────────────────────────────────────────┐               │
│  │  Keyed State (Partitioned by device_id)  │               │
│  │                                           │               │
│  │  sensor_001 → Window[12:00-12:01]        │               │
│  │    └─ Accumulator { count=1800, ... }    │               │
│  │                                           │               │
│  │  sensor_002 → Window[12:00-12:01]        │               │
│  │    └─ Accumulator { count=1850, ... }    │               │
│  │                                           │               │
│  │  ... (hundreds of devices)               │               │
│  └──────────────────────────────────────────┘               │
│           │                                                  │
│           │ Stored in RocksDB (on local disk)               │
│           ▼                                                  │
│  ┌──────────────────────────────────────────┐               │
│  │  RocksDB State Backend                   │               │
│  │  - Embedded key-value store              │               │
│  │  - Spills to disk when too large         │               │
│  │  - Incremental checkpointing             │               │
│  └──────────────────────────────────────────┘               │
└─────────────┬────────────────────────────────────────────────┘
              │
              │ Every 60 seconds (checkpoint interval)
              ▼
┌─────────────────────────────────────────────────────────────┐
│  S3 Checkpoint Storage                                       │
│  s3://s3-platform-flink/flink-checkpoints/low-infra/         │
│                                                              │
│  ├─ checkpoint_1/                                            │
│  │  ├─ _metadata                                             │
│  │  └─ rocksdb_state_snapshot/                              │
│  │     └─ all_window_accumulators.sst                       │
│  │                                                           │
│  ├─ checkpoint_2/ (incremental from checkpoint_1)           │
│  └─ checkpoint_3/ (incremental from checkpoint_2)           │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔄 State Lifecycle

### **1. Window Creation (e.g., 12:00:00)**

```
Event: First message arrives for device_001 in [12:00-12:01] window

Actions:
1. Flink creates new window state keyed by (device_id, window_time)
2. Initialize Accumulator:
   - count = 0
   - all sums = 0.0
   - all mins = Double.MAX_VALUE
   - all maxs = Double.MIN_VALUE
3. Store in RocksDB

State Size: ~500 bytes per device
```

### **2. Message Processing (12:00:00 - 12:00:59)**

```
For each incoming message (30K/sec):

1. Extract key: device_id = "sensor_001"
2. Lookup window state in RocksDB
3. Read current Accumulator
4. Update Accumulator:
   - count++
   - temp_sum += record.temperature
   - temp_min = min(temp_min, record.temperature)
   - temp_max = max(temp_max, record.temperature)
   - ... (all other metrics)
5. Write updated Accumulator back to RocksDB

State Updates: ~30K writes/sec to RocksDB
RocksDB handles this efficiently with LSM trees
```

### **3. Checkpointing (Every 60 seconds)**

```
Event: Flink initiates checkpoint

Actions:
1. Pause processing momentarily
2. RocksDB creates incremental snapshot
3. Upload only changed data to S3
4. Pulsar consumer acknowledges all messages processed before checkpoint
5. Resume processing

Checkpoint Contents:
├─ All active window states (~250 KB for 500 devices)
├─ Pulsar consumer offsets
├─ Operator state
└─ Metadata

Checkpoint Size: ~1-2 MB (very small due to incremental)
Checkpoint Duration: ~1-5 seconds
```

### **4. Window Closing (12:01:00)**

```
Event: Window [12:00-12:01] ends

Actions:
1. Read final Accumulator from state
2. Compute aggregated result:
   - temperature = temp_sum / count
   - humidity = hum_sum / count
   - ... (all averages)
3. Create SensorRecord with aggregated values
4. Emit to ClickHouse sink
5. Delete window state from RocksDB
6. Free memory

State Freed: ~500 bytes per device
```

---

## 💾 State Size Calculation

### **Scenario: 500 Unique Devices, 30K msgs/sec**

#### **At Any Given Moment:**

```
Active windows per device: 1 (current 1-minute window)
State per device window: ~500 bytes

Total State Size:
= 500 devices × 500 bytes
= 250 KB

With RocksDB overhead: ~500 KB - 1 MB
```

#### **Peak State Size (worst case):**

```
If windows overlap due to late data (rare with processing time):
= 500 devices × 2 windows × 500 bytes
= 500 KB

With RocksDB overhead: ~1-2 MB
```

#### **Checkpoint Storage (S3):**

```
First checkpoint: ~1-2 MB (full snapshot)
Subsequent checkpoints: ~100-500 KB each (incremental)

After 100 checkpoints with retention=3:
Total S3 storage: ~5-10 MB
```

**Conclusion: State size is very small and manageable!** ✅

---

## 🔧 State Backend Configuration

### **Current Configuration (from flink-job-deployment.yaml):**

```yaml
flinkConfiguration:
  # State Backend
  state.backend: rocksdb                    # Embedded key-value store
  state.backend.incremental: "true"         # Only checkpoint deltas
  
  # Checkpoint Storage
  state.checkpoints.dir: s3://s3-platform-flink/flink-checkpoints/low-infra/
  state.savepoints.dir: s3://s3-platform-flink/flink-savepoints/low-infra/
  
  # Checkpoint Frequency
  execution.checkpointing.interval: "60s"   # Every 60 seconds
  execution.checkpointing.mode: EXACTLY_ONCE
  execution.checkpointing.timeout: "10min"
  execution.checkpointing.max-concurrent-checkpoints: "1"
  execution.checkpointing.min-pause: "30s"
  
  # Checkpoint Retention
  execution.checkpointing.externalized-checkpoint-retention: RETAIN_ON_CANCELLATION
  execution.checkpointing.num-retained: "3"  # Keep last 3
  
  # RocksDB Tuning
  state.backend.rocksdb.predefined-options: SPINNING_DISK_OPTIMIZED_HIGH_MEM
  state.backend.rocksdb.thread.num: "4"
```

### **Why RocksDB?**

| Feature | RocksDB | Heap (In-Memory) |
|---------|---------|------------------|
| **State Size Limit** | Disk size (TBs) | JVM heap (GBs) |
| **Memory Usage** | Low (off-heap) | High (in-heap) |
| **Checkpoint Speed** | Fast (incremental) | Slow (full copy) |
| **Recovery Speed** | Medium | Fast |
| **Best For** | Large state | Small state |

**For 500 devices × 500 bytes = 250 KB**: Either works, but RocksDB is better for production!

---

## 🔍 Monitoring State

### **1. Check State Size via Flink Web UI**

```bash
# Port-forward Flink UI
kubectl port-forward -n flink-benchmark svc/iot-flink-job-rest 8081:8081

# Open browser: http://localhost:8081

Navigate to:
├─ Running Jobs
│  └─ Click on your job
│     └─ State tab
│        ├─ State Size: Shows total state across all operators
│        ├─ State Backend: Shows RocksDB
│        └─ Checkpoint Statistics
```

### **2. Check Checkpoint Metrics**

```bash
# View checkpoint history
curl http://localhost:8081/jobs/<job-id>/checkpoints

# Response shows:
{
  "latest_checkpoints": {
    "completed": {
      "id": 42,
      "status": "COMPLETED",
      "external_path": "s3://...",
      "state_size": 1048576,  # 1 MB
      "duration": 2345,       # 2.3 seconds
      "num_acknowledged_subtasks": 8
    }
  }
}
```

### **3. Check S3 Storage**

```bash
# List checkpoints in S3
aws s3 ls s3://s3-platform-flink/flink-checkpoints/low-infra/ --recursive --human-readable

# Output:
2024-10-10 12:01:00  1.2 MB  chk-42/_metadata
2024-10-10 12:01:00  500 KB  chk-42/shared/state-001.sst
2024-10-10 12:02:00  1.3 MB  chk-43/_metadata
2024-10-10 12:02:00  150 KB  chk-43/shared/state-002.sst  # Incremental!
```

### **4. Monitor State in Logs**

```bash
# Check for state-related warnings
kubectl logs -n flink-benchmark -l app=iot-flink-job | grep -i "state\|checkpoint"

# Expected healthy output:
# INFO  Completed checkpoint 42 for job <job-id> (1234 bytes, 2.3 sec)
# INFO  Checkpoint 42 acknowledged by all tasks
```

---

## ⚡ State Performance Optimization

### **Current Settings (Already Optimized):**

```yaml
# RocksDB Performance Tuning
state.backend.rocksdb.predefined-options: SPINNING_DISK_OPTIMIZED_HIGH_MEM
  └─ Uses more memory for better write performance
  
state.backend.rocksdb.thread.num: "4"
  └─ 4 background threads for compaction

state.backend.incremental: "true"
  └─ Only upload changed data (much faster)
```

### **If You Need More Performance:**

#### **1. Increase RocksDB Block Cache**

```yaml
state.backend.rocksdb.block.cache-size: "512m"  # More cache = faster reads
```

#### **2. Increase Write Buffer Size**

```yaml
state.backend.rocksdb.writebuffer.size: "128m"  # Larger write buffers
state.backend.rocksdb.writebuffer.count: "4"    # More buffers
```

#### **3. Use Local SSDs (if available)**

```yaml
# In TaskManager podTemplate
volumes:
- name: rocksdb-local-ssd
  hostPath:
    path: /mnt/local-ssd  # Faster than EBS
    
volumeMounts:
- name: rocksdb-local-ssd
  mountPath: /tmp/flink-rocksdb
```

---

## 🛡️ Fault Tolerance with State

### **Scenario: TaskManager Crashes**

```
Time: 12:00:30 - TaskManager crashes mid-window

What Happens:
1. Flink JobManager detects failure
2. Restarts failed tasks on another TaskManager
3. Recovers from last checkpoint (12:00:00)
4. Reprocesses messages from Pulsar since checkpoint
5. Rebuilds window state
6. Continues processing

Result: No data loss, exactly-once processing guaranteed!
```

### **Scenario: Entire Job Restart**

```bash
# Manually restart job
kubectl delete flinkdeployment iot-flink-job -n flink-benchmark
kubectl apply -f flink-job-deployment.yaml

What Happens:
1. New job starts
2. Looks for latest checkpoint in S3
3. Restores all window state from checkpoint
4. Reconnects to Pulsar at saved offset
5. Continues from where it left off

Result: Seamless recovery!
```

---

## 📊 State vs Memory Trade-offs

### **Small State (250 KB) - Current Setup**

```
✅ Advantages:
- Fast checkpoints (~1-2 seconds)
- Low memory usage
- Quick recovery
- Minimal S3 storage costs

✅ Recommended Configuration:
- RocksDB backend (already configured)
- 60-second checkpoint interval (already configured)
- Keep last 3 checkpoints (already configured)
```

### **If State Grows Large (e.g., 1-hour windows)**

```
With 1-hour windows instead of 1-minute:
- State size: 500 devices × 60 windows × 500 bytes = 15 MB
- Still manageable!

Adjustments needed:
- Increase checkpoint interval to 120s
- Increase RocksDB cache
- Monitor state size growth
```

---

## 🔍 Debugging State Issues

### **Problem: Checkpoints Taking Too Long**

```bash
# Check checkpoint duration
kubectl logs -n flink-benchmark -l app=iot-flink-job | grep "checkpoint.*duration"

# If > 30 seconds:
1. Check S3 upload speed (network issue?)
2. Increase checkpoint timeout
3. Enable incremental checkpoints (already enabled)
4. Reduce checkpoint frequency (60s → 120s)
```

### **Problem: Out of Memory Errors**

```bash
# Check TaskManager memory
kubectl top pods -n flink-benchmark | grep taskmanager

# If memory is maxed:
1. Increase TaskManager memory in YAML
2. Reduce state size (smaller windows?)
3. Increase RocksDB off-heap memory
4. Add more TaskManagers
```

### **Problem: State Growing Unexpectedly**

```bash
# Check state size trend
curl http://localhost:8081/jobs/<job-id>/checkpoints/details/<checkpoint-id>

# If growing continuously:
1. Check for late data piling up
2. Verify windows are closing properly
3. Check for duplicate device_ids
4. Review window configuration
```

---

## 📈 State Size Projections

### **Current (1-minute windows, 500 devices):**
- State: **250 KB**
- Checkpoints: **1-2 MB**
- S3 storage: **5-10 MB** (with retention)

### **Scaled Up (5-minute windows, 500 devices):**
- State: **1.25 MB** (5× larger)
- Checkpoints: **2-3 MB**
- S3 storage: **10-15 MB**

### **Scaled Up (1-minute windows, 5000 devices):**
- State: **2.5 MB** (10× more devices)
- Checkpoints: **5-8 MB**
- S3 storage: **20-30 MB**

### **Scaled Up (1-hour windows, 5000 devices):**
- State: **150 MB** (60× window × 10× devices)
- Checkpoints: **200-300 MB**
- S3 storage: **1-2 GB**
- **Note:** May need additional tuning at this scale

---

## 💡 Best Practices

### ✅ **DO:**

1. **Use RocksDB** for production (already configured)
2. **Enable incremental checkpoints** (already enabled)
3. **Monitor state size** regularly
4. **Keep checkpoint interval reasonable** (60-120s)
5. **Retain 2-3 checkpoints** for safety (already configured)
6. **Use S3 for checkpoint storage** (already configured)

### ❌ **DON'T:**

1. Don't use heap state backend for large state
2. Don't set checkpoint interval too low (<30s)
3. Don't retain too many checkpoints (wastes S3 space)
4. Don't ignore checkpoint failures
5. Don't disable incremental checkpoints for large state

---

## 📚 Summary

### **Your Windowed Aggregation State:**

| Aspect | Details |
|--------|---------|
| **State Backend** | RocksDB (embedded key-value store) |
| **Storage Location** | Local disk + S3 checkpoints |
| **State Size** | ~250 KB (500 devices × 500 bytes) |
| **Checkpoint Size** | ~1-2 MB (initial), ~100-500 KB (incremental) |
| **Checkpoint Frequency** | Every 60 seconds |
| **Recovery Time** | ~5-10 seconds |
| **Data Loss Risk** | Zero (exactly-once processing) |
| **Scalability** | Easily handles 10,000+ devices |

### **Key Takeaways:**

1. ✅ **Yes, all window values are stored in state** (RocksDB)
2. ✅ **State size is very small** (~250 KB for 500 devices)
3. ✅ **Checkpoints are fast** (~1-5 seconds)
4. ✅ **Fault tolerance is guaranteed** (S3 checkpoints)
5. ✅ **Current configuration is optimal** for your use case!

**Your state management is production-ready!** 🚀

