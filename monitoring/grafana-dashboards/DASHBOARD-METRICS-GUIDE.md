# Flink Grafana Dashboard - Aggregation Metrics Guide

## 📊 New Panels Added

Added **6 new panels** to track the complete data flow through the 1-minute aggregation pipeline.

---

## 🎯 Panel 1: Pipeline Source - Raw Messages from Pulsar

**Type**: Time Series Graph  
**Location**: Row 4, Left Side  
**Metric**: `flink_taskmanager_job_task_operator_numRecordsOutPerSecond{operator_name=~".*Source.*Pulsar.*"}`

**Shows**:
- Raw messages consumed from Pulsar per second
- This is the **input rate** before aggregation
- Expected: ~30K msgs/sec when producer is running

**Use Case**: 
- Verify Pulsar consumption rate
- Detect if source is under-performing

---

## 🎯 Panel 2: Aggregation Window - 1-Minute Reduction

**Type**: Time Series Graph with 2 Metrics  
**Location**: Row 4, Right Side  

### Metrics:
1. **Window IN (Raw)** - Blue Line
   - `flink_taskmanager_job_task_operator_numRecordsInPerSecond{operator_name=~".*TumblingProcessingTimeWindows.*"}`
   - Raw messages entering the window operator

2. **Window OUT (Aggregated)** - Green Line
   - `flink_taskmanager_job_task_operator_numRecordsOutPerSecond{operator_name=~".*TumblingProcessingTimeWindows.*"}`
   - Aggregated records leaving the window operator

**Shows**:
- Visual comparison of IN vs OUT
- Gap between lines = aggregation reduction
- **Expected**: Large gap (e.g., 30K in → 8/sec out)

**Use Case**:
- Verify aggregation is working
- See the reduction ratio visually
- Troubleshoot if gap is too small

---

## 🎯 Panel 3: ClickHouse Sink - Writes Per Second

**Type**: Stat Panel (Single Value)  
**Location**: Row 5, Position 1  
**Metric**: `sum(rate(flink_taskmanager_job_task_operator_numRecordsIn{operator_name=~".*Sink.*"}[1m]))`

**Shows**:
- Current write rate to ClickHouse
- **Expected**: ~8-10 writes/sec (with 500 devices, 1-minute windows)
- **Thresholds**:
  - Green: < 500 writes/sec
  - Yellow: 500-1000 writes/sec
  - Red: > 1000 writes/sec

**Use Case**:
- Monitor ClickHouse load
- Alert if writes are too high (aggregation not working)

---

## 🎯 Panel 4: Aggregation Reduction %

**Type**: Stat Panel (Percentage)  
**Location**: Row 5, Position 2  
**Formula**: `(1 - (WindowOUT / WindowIN)) * 100`

**Shows**:
- Percentage of data reduced by aggregation
- **Expected**: 95-99% reduction
- **Thresholds**:
  - Red: < 50% (aggregation failing!)
  - Yellow: 50-95% (partial aggregation)
  - Green: > 95% (working well)

**Use Case**:
- Quick health check of aggregation
- Alert if reduction drops below 95%

---

## 🎯 Panel 5: Total Raw Messages Consumed

**Type**: Stat Panel (Counter)  
**Location**: Row 5, Position 3  
**Metric**: `sum(flink_taskmanager_job_task_operator_numRecordsOut{operator_name=~".*Source.*Pulsar.*"})`

**Shows**:
- Total messages consumed from Pulsar since job start
- Continuously incrementing counter

**Use Case**:
- Track total throughput
- Verify continuous consumption

---

## 🎯 Panel 6: Total Aggregated Records Written

**Type**: Stat Panel (Counter)  
**Location**: Row 5, Position 4  
**Metric**: `sum(flink_taskmanager_job_task_operator_numRecordsOut{operator_name=~".*TumblingProcessingTimeWindows.*"})`

**Shows**:
- Total aggregated records written to ClickHouse
- Continuously incrementing counter

**Use Case**:
- Compare with Panel 5 to see reduction ratio
- Verify continuous aggregation

---

## 📈 Example Dashboard View

```
┌─────────────────────────────────────────────────────────────┐
│ Row 4:                                                      │
├─────────────────────────────┬───────────────────────────────┤
│ Pipeline Source             │ Aggregation Window            │
│ Raw Messages from Pulsar    │ 1-Minute Reduction            │
│                             │                               │
│ [Graph: ~30K msgs/sec]      │ [Graph: Blue (30K) vs        │
│                             │         Green (8/sec)]        │
└─────────────────────────────┴───────────────────────────────┘

┌──────────┬──────────┬──────────┬──────────┐
│ Row 5:                                     │
├──────────┼──────────┼──────────┼──────────┤
│ ClickHouse│ Aggreg.  │ Total Raw│ Total    │
│ Writes    │ Reduction│ Messages │ Aggreg.  │
│           │          │          │ Records  │
│  8/sec    │  99.7%   │ 600,090  │ 432,657  │
│  GREEN    │  GREEN   │          │          │
└──────────┴──────────┴──────────┴──────────┘
```

---

## 🔍 Metrics Queries Reference

### Source Metrics (Pulsar)
```promql
# Records out per second
sum(flink_taskmanager_job_task_operator_numRecordsOutPerSecond{operator_name=~".*Source.*Pulsar.*"})

# Total records consumed
sum(flink_taskmanager_job_task_operator_numRecordsOut{operator_name=~".*Source.*Pulsar.*"})
```

### Window Aggregation Metrics
```promql
# Window IN (raw messages)
sum(flink_taskmanager_job_task_operator_numRecordsInPerSecond{operator_name=~".*TumblingProcessingTimeWindows.*"})

# Window OUT (aggregated records)
sum(flink_taskmanager_job_task_operator_numRecordsOutPerSecond{operator_name=~".*TumblingProcessingTimeWindows.*"})

# Total aggregated records
sum(flink_taskmanager_job_task_operator_numRecordsOut{operator_name=~".*TumblingProcessingTimeWindows.*"})
```

### Sink Metrics (ClickHouse)
```promql
# Writes per second (rate over 1 minute)
sum(rate(flink_taskmanager_job_task_operator_numRecordsIn{operator_name=~".*Sink.*"}[1m]))

# Total records written
sum(flink_taskmanager_job_task_operator_numRecordsIn{operator_name=~".*Sink.*"})
```

### Calculated Metrics
```promql
# Aggregation reduction percentage
(1 - (sum(flink_taskmanager_job_task_operator_numRecordsOutPerSecond{operator_name=~".*TumblingProcessingTimeWindows.*"}) / sum(flink_taskmanager_job_task_operator_numRecordsInPerSecond{operator_name=~".*TumblingProcessingTimeWindows.*"}))) * 100
```

---

## 🚀 How to Import Dashboard

### Option 1: Via Grafana UI
```bash
1. Access Grafana:
   kubectl port-forward -n grafana svc/grafana 3000:80

2. Open browser: http://localhost:3000

3. Login (default: admin/admin)

4. Import Dashboard:
   - Click "+" → Import
   - Upload file: grafana-dashboards/flink-dashboard.json
   - Select Prometheus datasource
   - Click Import
```

### Option 2: Via Script
```bash
cd /Users/vijayabhaskarv/IOT/datapipeline-0/Flink-Benchmark/low_infra_flink/grafana-dashboards

# Run import script
./import-dashboards.sh
```

---

## 📊 Interpreting the Metrics

### Healthy Pipeline (Expected)
```
Source OUT:        30,000 msgs/sec  ✅
Window IN:         30,000 msgs/sec  ✅
Window OUT:             8 msgs/sec  ✅
Sink IN:                8 msgs/sec  ✅
Reduction %:             99.97%     ✅
```

### Problematic Pipeline (Current Issue)
```
Source OUT:         ~800 msgs/sec   ⚠️  (low producer rate)
Window IN:          ~800 msgs/sec   ✅
Window OUT:         ~720 msgs/sec   ❌  (should be ~8/sec!)
Sink IN:            ~720 msgs/sec   ❌  (39K/min = 650/sec)
Reduction %:            10%         ❌  (should be 99%+)
```

**Problem**: Window aggregation is NOT working! Only 10% reduction instead of 99%.

**Possible Causes**:
1. Window is not keyed correctly (all records in one key?)
2. Window size is wrong
3. Aggregation function not triggering
4. Data structure issues

---

## 🔧 Troubleshooting

### Issue: Aggregation Reduction < 50%

**Check**:
1. Verify window configuration in code
2. Check if keyBy is working (should be by device_id)
3. Look at aggregation logs for window closure

**Fix**:
- Review JDBCFlinkConsumer.java aggregation logic
- Ensure `.keyBy(record -> record.device_id)` is correct
- Check if devices have unique IDs

### Issue: ClickHouse Writes Too High

If ClickHouse writes are > 1000/sec:
1. Check "Aggregation Reduction %" panel
2. If low, aggregation is broken
3. Check Flink logs for errors

### Issue: Metrics Not Showing

If panels show "No Data":
1. Verify Prometheus is scraping Flink metrics:
   ```bash
   kubectl get servicemonitor -n flink-benchmark
   ```
2. Check Flink metrics are exposed:
   ```bash
   curl http://localhost:8081/jobs/<job-id>/metrics
   ```
3. Verify Prometheus datasource in Grafana

---

## 🎯 Key Insights from Current Metrics

### What We Discovered:
```
Raw Messages IN:         600,090 records
Window Aggregation OUT:  432,657 records  (72% of input!)
Expected Window OUT:       ~500 records   (0.08% of input)

PROBLEM: Only 28% reduction instead of 99%+
```

### This Means:
- ❌ Aggregation is NOT working as designed
- ❌ Most records passing through without aggregation
- ❌ ClickHouse getting 39,000 writes/min instead of 500/min
- ⚠️  Need to investigate window aggregation logic

---

## 📝 Next Steps

1. **Monitor Dashboard**: Watch the new panels to track aggregation performance

2. **Investigate**: If reduction % is low:
   - Check Flink logs for aggregation window closures
   - Verify device_id keying is working
   - Review SensorAggregator logic

3. **Alert Setup**: Configure Grafana alerts:
   - Alert if "Aggregation Reduction %" < 95%
   - Alert if "ClickHouse Writes" > 100/sec

4. **Optimize**: Once working, tune:
   - Window size (currently 1 minute)
   - Batch size (currently 1000)
   - Parallelism (currently 8)

---

## 📚 Related Documentation

- **Flink Metrics**: https://nightlies.apache.org/flink/flink-docs-stable/docs/ops/metrics/
- **Prometheus Queries**: https://prometheus.io/docs/prometheus/latest/querying/basics/
- **Grafana Dashboards**: https://grafana.com/docs/grafana/latest/dashboards/

---

**Dashboard Updated**: October 10, 2025  
**File**: `grafana-dashboards/flink-dashboard.json`  
**Panels Added**: 6 new aggregation metrics panels

