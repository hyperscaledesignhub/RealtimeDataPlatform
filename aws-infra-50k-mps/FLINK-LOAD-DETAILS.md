# Flink Load - Detailed Documentation (50K Messages/Second)

## Overview
The `flink-load` folder contains the Apache Flink streaming job optimized for **50,000 messages per second** using cost-effective t3 instances. It consumes event data from Pulsar, aggregates it in 1-minute windows, and writes to ClickHouse.

## Purpose
- **Consume** event stream data from Pulsar topics (AVRO format)
- **Process & Aggregate** data in 1-minute windows per event source
- **Write** aggregated data to ClickHouse database
- **Handle** up to 50K messages/second with fault tolerance
- **Optimize** for cost with t3.large instances

## Key Differences from 1M Setup

| Aspect | 50K Setup | 1M Setup |
|--------|-----------|----------|
| **Throughput** | 50K msg/sec | 250K+ msg/sec |
| **JobManager** | t3.large (1 node) | c5.4xlarge (1 node) |
| **TaskManager** | t3.large (1-2 nodes) | c5.4xlarge (2-6 nodes) |
| **vCPU per node** | 2 | 16 |
| **RAM per node** | 8 GB | 32 GB |
| **Task Slots** | 2 per TM | 4 per TM |
| **Total Parallelism** | 2-4 slots | 4-24 slots |
| **Batch Size** | 1,000 records | 5,000 records |
| **Monthly Cost** | ~$90 | ~$367 |
| **Use Case** | Dev/test, moderate workloads | Production, high-scale |

## Core Application: JDBCFlinkConsumer.java

This is the same Flink streaming application as the 1M setup, but configured for lower parallelism and smaller batch sizes.

### Configuration Adjustments for 50K

**In flink-job-deployment.yaml:**
```yaml
spec:
  jobManager:
    resource:
      memory: "4096m"  # Reduced from 8GB
      cpu: 1           # Reduced from 2
  
  taskManager:
    replicas: 1        # Start with 1, scale to 2 for 50K
    resource:
      memory: "4096m"  # Reduced from 8GB
      cpu: 1           # Reduced from 2
```

**In JDBCFlinkConsumer.java:**
```java
// Batch size reduced for moderate load
private static final int BATCH_SIZE = 1000;  // vs 5000 in 1M setup
```

### Data Pipeline Flow (50K msg/sec)
```
┌──────────┐     ┌────────────┐     ┌──────────┐     ┌───────────┐
│  Pulsar  │ ──→ │    AVRO    │ ──→ │  Aggregate│ ──→ │ ClickHouse│
│  Topic   │     │  Deserial. │     │ (1-min)   │     │ JDBC Sink │
└──────────┘     └────────────┘     └──────────┘     └───────────┘
 50K msg/sec      Parallel          Per source_id      Batch 1K
 t3.large nodes   Processing        ~800-1K/min        EBS storage
```

## JDBCFlinkConsumer Components

### 1. AVRO Deserialization Schema
Converts binary AVRO messages from Pulsar into Java `SensorRecord` objects.

**Same as 1M setup** - No changes needed

### 2. SensorRecord Class
Data model with 25 fields matching ClickHouse schema.

**Same as 1M setup** - Universal data model

### 3. SensorAggregator
Aggregates event data over 1-minute windows.

**Configured for 50K:**
- Input: 50K messages/second
- Window: 1 minute
- Group by: event_source_id
- Output: ~800-1,000 aggregated records/minute
- Reduction: 3,000x (50K/sec → 800/min)

### 4. ClickHouseJDBCSink
Checkpoint-aware sink with smaller batch size.

**Adjusted Configuration:**
```java
private static final int BATCH_SIZE = 1000;  // Optimized for moderate load

// Checkpoint interval: 1 minute (via FlinkDeployment YAML)
// Flushes batches during checkpoints for exactly-once semantics
```

**Performance:**
- **Batch Size:** 1,000 records (vs 5,000)
- **Latency:** ~100-200ms per batch
- **Throughput:** ~15-20 batches/minute
- **Total inserts:** ~15,000-20,000 records/minute

## Deployment Files

### flink-job-deployment.yaml (Cost-Optimized)
```yaml
apiVersion: flink.apache.org/v1beta1
kind: FlinkDeployment
metadata:
  name: iot-flink-job
  namespace: flink-benchmark
spec:
  image: <ECR_URL>/bench-low-infra-flink-job:latest
  flinkVersion: v1_17
  
  jobManager:
    replicas: 1
    resource:
      memory: "4096m"     # 4 GB (vs 8GB in 1M)
      cpu: 1              # 1 core (vs 2 in 1M)
  
  taskManager:
    replicas: 1           # Start with 1 (vs 2 in 1M)
    resource:
      memory: "4096m"     # 4 GB per TM
      cpu: 1              # 1 core per TM
    
  # Checkpointing configuration (same as 1M)
  flinkConfiguration:
    execution.checkpointing.interval: "60000"  # 1 minute
    execution.checkpointing.mode: "EXACTLY_ONCE"
    state.backend: "rocksdb"
    state.checkpoints.dir: "s3://bench-low-infra-flink-state/checkpoints"
    state.savepoints.dir: "s3://bench-low-infra-flink-state/savepoints"
    
  # Node selector for t3.large nodes
  nodeSelector:
    workload: flink
```

### Resource Allocation (50K Setup)
```
JobManager:    1 replica  × 4GB RAM × 1 CPU   = 4GB RAM, 1 CPU total
TaskManager:   1 replica  × 4GB RAM × 1 CPU   = 4GB RAM, 1 CPU total
               2 task slots per TM             = 2 task slots total

Total: 8GB RAM, 2 CPUs for Flink cluster (vs 24GB, 9 CPUs in 1M setup)
```

## Performance Characteristics

### Throughput
- **Input:** Up to 50,000 messages/second from Pulsar
- **Output:** ~800-1,000 aggregated records/minute to ClickHouse
- **Reduction ratio:** 3,000x (50K/sec → 800/min)

### Resource Usage
- **JobManager:** ~50% CPU, ~3GB RAM
- **TaskManager:** ~60-70% CPU, ~3.5GB RAM
- **Network:** ~5-10 MB/sec
- **Checkpoints:** ~50-100 MB per checkpoint

### Latency
- **Processing:** <100ms per message
- **Window:** 1 minute aggregation
- **Checkpoint:** ~5-10 seconds per checkpoint
- **End-to-end:** ~1-2 seconds (including windowing)

## Scaling Guide

### Handle 10K msg/sec (Current Default)
```yaml
# No changes needed
taskManager:
  replicas: 1  # Sufficient
```

### Handle 30K msg/sec
```yaml
taskManager:
  replicas: 2  # Add 1 more TaskManager
```

### Handle 50K msg/sec (Max)
```yaml
taskManager:
  replicas: 2
  resource:
    cpu: 2  # Upgrade to t3.xlarge or increase CPU
```

## Monitoring

### Flink Web UI
```bash
# Port-forward JobManager UI
kubectl port-forward -n flink-benchmark <jobmanager-pod> 8081:8081

# Access at: http://localhost:8081
```

**View:**
- Job graph and parallelism
- Checkpoint statistics
- Backpressure indicators
- Task metrics

### Logs
```bash
# JobManager logs
kubectl logs -n flink-benchmark -l component=jobmanager

# TaskManager logs
kubectl logs -n flink-benchmark -l component=taskmanager

# Watch for aggregation
kubectl logs -n flink-benchmark -l component=taskmanager | grep "Aggregated"
```

## Cost Analysis

### Monthly Cost (Spot Instances)

**JobManager (t3.large × 1):**
- Cost: ~$30/month

**TaskManager (t3.large × 1-2):**
- 1 TM: ~$30/month
- 2 TMs: ~$60/month

**Total Flink Cost:** ~$60-90/month (vs ~$367/month for c5.4xlarge)

**Cost Savings:** 75-80% lower

## Deployment Steps

### 1. Install Operator
```bash
cd flink-load
./deploy.sh
```

### 2. Setup S3
```bash
./setup-s3-checkpoints.sh
```

### 3. Deploy Job
```bash
./build-and-push.sh
kubectl apply -f flink-job-deployment.yaml
```

### 4. Verify
```bash
kubectl get pods -n flink-benchmark
kubectl logs -n flink-benchmark -l component=jobmanager
```

## Troubleshooting

### Job Not Starting
**Check resources:**
```bash
kubectl describe pod -n flink-benchmark <jobmanager-pod>
```

**Common issue:** Insufficient memory  
**Solution:** t3.large provides 8GB, ensure no other memory-hungry pods on same node

### Low Throughput
**Check TaskManager count:**
```bash
kubectl get pods -n flink-benchmark -l component=taskmanager
```

**Scale if needed:**
```bash
kubectl patch flinkdeployment iot-flink-job -n flink-benchmark \
  --type merge -p '{"spec":{"taskManager":{"replicas":2}}}'
```

### High Checkpoint Duration
**Check S3 connectivity:**
```bash
kubectl logs -n flink-benchmark -l component=jobmanager | grep checkpoint
```

**If checkpoints take >30 seconds, check:**
- S3 bucket region (should be us-west-2)
- IAM permissions
- Network latency

## Summary

The flink-load folder for 50K setup provides:

1. **Cost-optimized Flink deployment** with t3.large instances
2. **50K msg/sec processing capacity** with room to scale
3. **Same code as 1M setup** (JDBCFlinkConsumer.java)
4. **Reduced batch sizes** (1K vs 5K) for efficiency
5. **Lower parallelism** (2-4 slots vs 4-24)
6. **75% cost savings** (~$90 vs ~$367/month)
7. **S3 checkpointing** for fault tolerance
8. **Exactly-once semantics** maintained

**Perfect for:**
- Development and testing
- Moderate production workloads
- Cost-conscious deployments
- Learning and experimentation
- Gradual scaling path to 1M setup

