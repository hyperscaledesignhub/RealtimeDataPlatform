# Pulsar Load - Detailed Documentation (50K Messages/Second)

## Overview
The `pulsar-load` folder contains all components to deploy Apache Pulsar as a cost-optimized message broker for moderate-scale event streaming up to **50,000 messages per second**.

## Purpose
- **Deploy** Apache Pulsar on Kubernetes (EKS) with cost-effective t3 instances
- **Configure** for moderate-throughput event ingestion (50K msg/sec)
- **Provide** durable message storage using EBS volumes
- **Optimize** for cost (~$100-150/month vs $4,992/month for NVMe setup)

## Key Differences from 1M Setup

| Aspect | 50K Setup | 1M Setup |
|--------|-----------|----------|
| **Throughput** | 50K msg/sec | 250K+ msg/sec |
| **Instance Types** | t3.small/large | i7i.8xlarge |
| **Storage** | EBS gp3 | NVMe SSD |
| **ZooKeeper** | t3.small × 3 | t3.medium × 3 |
| **Broker** | t3.large × 2-4 | i7i.8xlarge × 4-8 |
| **BookKeeper** | t3.large × 2-4 (EBS) | i7i.8xlarge × 4-8 (NVMe) |
| **Proxy** | t3.medium × 1-2 | c5.2xlarge × 2 |
| **Monthly Cost** | ~$125 | ~$4,992 |
| **Latency (p99)** | <20ms | <10ms |

## Key Components

### 1. Helm Deployment
**Location:** `helm/pulsar/`

Contains the official Apache Pulsar Helm chart with templates for all components.

### 2. Configuration File: pulsar-values.yaml
**Purpose:** Custom Helm values optimized for cost and moderate throughput

**Key Configurations:**
```yaml
# ZooKeeper (Cost-optimized)
zookeeper:
  replicas: 3
  resources:
    requests:
      cpu: 200m
      memory: 512Mi
    limits:
      cpu: 500m
      memory: 1Gi
  storage:
    type: ebs-gp3
    size: 20Gi

# Broker (Cost-optimized)
broker:
  replicas: 2  # Start with 2, scale to 4 for 50K
  resources:
    requests:
      cpu: 1000m
      memory: 2Gi
    limits:
      cpu: 2000m
      memory: 4Gi

# BookKeeper (EBS storage)
bookkeeper:
  replicas: 2  # Start with 2, scale to 4 for 50K
  journal:
    storage: ebs-gp3
    size: 50Gi
  ledger:
    storage: ebs-gp3
    size: 100Gi
  resources:
    requests:
      cpu: 1000m
      memory: 2Gi
    limits:
      cpu: 2000m
      memory: 4Gi

# Proxy (Cost-optimized)
proxy:
  replicas: 1  # Scale to 2 for higher load
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 1000m
      memory: 2Gi
```

**Cost Optimizations:**
- **t3 instances:** Burstable CPU for cost savings
- **EBS storage:** gp3 volumes instead of expensive NVMe
- **Fewer replicas:** 2-4 brokers vs 4-8 in high-scale setup
- **Spot instances:** Optional for 60-70% savings

### 3. Performance Testing

#### pulsar-sensor-perf
**Purpose:** Moderate-scale event data generator

**Usage for 50K msg/sec:**
```bash
./pulsar-sensor-perf iot-produce \
  --device-id-min 1 \
  --device-id-max 10000 \
  --rate 50000 \
  --topics persistent://public/default/event-stream-data \
  --service-url pulsar://localhost:6650
```

**Configuration:**
- 10,000 unique event sources (vs 100K in 1M setup)
- Up to 50K messages/second total
- AVRO encoding
- Realistic event data

## Architecture

### Pulsar Cluster Components
```
┌────────────────────────────────────────────────────────┐
│             Cost-Optimized Pulsar Cluster              │
├────────────────────────────────────────────────────────┤
│                                                        │
│  ┌──────────────┐    ┌──────────────┐   ┌─────────┐  │
│  │  ZooKeeper   │←──→│    Broker    │←─→│  Proxy  │  │
│  │ t3.small ×3  │    │ t3.large ×2-4│   │t3.medium│  │
│  │  EBS 20GB    │    │   EBS 50GB   │   │  ×1-2   │  │
│  └──────────────┘    └──────┬───────┘   └─────────┘  │
│                              │                         │
│                              ↓                         │
│                      ┌──────────────┐                 │
│                      │ BookKeeper   │                 │
│                      │ t3.large ×2-4│                 │
│                      │  EBS Storage │                 │
│                      │ 100GB/bookie │                 │
│                      └──────────────┘                 │
└────────────────────────────────────────────────────────┘
```

## Performance Characteristics

### Throughput
- **Write:** Up to 50,000 messages/second
- **Read:** Parallel consumption via Flink
- **Latency:** <20ms p99 with EBS gp3

### Storage
- **Journal:** EBS gp3 (write-ahead log)
- **Ledger:** EBS gp3 (message storage)
- **Retention:** 7 days (configurable)
- **IOPS:** 3,000 baseline per volume

### Scalability
- **Current config:** 50K msg/sec
- **Scale to 100K:** Add 2 more brokers (t3.xlarge)
- **Cost per 10K msg/sec:** ~$25/month

## Topic Configuration

### Event Stream Data Topic
```
Name: persistent://public/default/event-stream-data
Type: Non-partitioned (or 2-4 partitions for higher throughput)
Replication: 2
Retention: 7 days
Compression: LZ4
Schema: AVRO (SensorData.avsc)
Throughput: Up to 50K msg/sec
```

## Monitoring

### Topic Statistics
```bash
kubectl exec -n pulsar pulsar-toolset-0 -- \
  bin/pulsar-admin topics stats persistent://public/default/event-stream-data
```

**Key metrics:**
- Message rate in/out
- Storage size (EBS)
- Subscription backlog
- Consumer lag

### Broker Metrics
```bash
kubectl exec -n pulsar pulsar-broker-0 -- \
  curl http://localhost:8080/metrics/
```

**Metrics to watch:**
- CPU usage (should be < 80% on t3.large)
- Memory usage (should be < 3.5GB)
- Message throughput
- Connection count

## Common Operations

### Create Topic (Non-Partitioned)
```bash
kubectl exec -n pulsar pulsar-toolset-0 -- \
  bin/pulsar-admin topics create \
  persistent://public/default/event-stream-data
```

### Create Partitioned Topic (for higher throughput)
```bash
kubectl exec -n pulsar pulsar-toolset-0 -- \
  bin/pulsar-admin topics create-partitioned-topic \
  persistent://public/default/event-stream-data \
  --partitions 4
```

### Set Retention Policy
```bash
kubectl exec -n pulsar pulsar-toolset-0 -- \
  bin/pulsar-admin namespaces set-retention public/default \
  --size 50G --time 7d
```

### Scale Brokers
```bash
# Update terraform.tfvars
pulsar_broker_desired_size = 4

# Apply
cd /Users/vijayabhaskarv/IOT/github/RealtimeDataPlatform/realtime-platform-50k-events
terraform apply
```

## Cost Analysis

### Component Costs (Spot Instances)

**ZooKeeper (t3.small × 3):**
- Cost: ~$9/month per node
- Total: ~$27/month

**Broker (t3.large × 3):**
- Cost: ~$30/month per node
- Total: ~$90/month

**BookKeeper (t3.large × 3 + EBS 100GB each):**
- Compute: ~$90/month
- Storage: ~$30/month (300 GB total)
- Total: ~$120/month

**Proxy (t3.medium × 1):**
- Cost: ~$12/month

**Total Pulsar Cost:** ~$250/month (spot) vs ~$5,000/month (NVMe setup)

## Deployment Steps

### 1. Provision Infrastructure
```bash
cd /Users/vijayabhaskarv/IOT/github/RealtimeDataPlatform/realtime-platform-50k-events
terraform apply
```

Creates EKS node groups with t3 instances for Pulsar

### 2. Deploy Pulsar
```bash
cd pulsar-load
./deploy.sh
```

Installs all Pulsar components with EBS storage

### 3. Verify Deployment
```bash
kubectl get pods -n pulsar
kubectl get pvc -n pulsar  # Should show EBS volumes bound
```

### 4. Test Producer
```bash
./test-iot-producer.sh
```

## Troubleshooting

### Pods Not Starting
**Check node groups:**
```bash
kubectl get nodes -l workload=pulsar
```

**Check PVC binding:**
```bash
kubectl get pvc -n pulsar
# All should be "Bound"
```

### Low Throughput
**Check broker resources:**
```bash
kubectl top pods -n pulsar | grep broker
```

**If CPU > 80%, scale up:**
```bash
# Option 1: Add more brokers
pulsar_broker_desired_size = 4
terraform apply

# Option 2: Upgrade instance type to t3.xlarge
```

### Storage Issues
**Check EBS volumes:**
```bash
kubectl get pvc -n pulsar
kubectl describe pvc <pvc-name> -n pulsar
```

**Monitor storage usage:**
```bash
kubectl exec -n pulsar bookie-0 -- df -h
```

## Summary

The pulsar-load folder for 50K setup provides:

1. **Cost-optimized Pulsar deployment** with t3 instances and EBS
2. **50K msg/sec capacity** with room to scale to 100K
3. **EBS persistent storage** (gp3 for cost-performance balance)
4. **7-day retention** with configurable policies
5. **90% cost savings** vs NVMe setup ($250 vs $5,000/month)
6. **Production-ready** with HA and monitoring
7. **Easy scaling** by adding more t3.large nodes

**Perfect for:**
- Development and testing
- Moderate production workloads
- Cost-conscious deployments
- Startups and SMBs
- Gradual scaling scenarios

