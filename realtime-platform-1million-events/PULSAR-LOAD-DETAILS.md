# Pulsar Load - Detailed Documentation

## Overview
The `pulsar-load` folder contains all components needed to deploy and configure Apache Pulsar as the high-throughput message broker for IoT sensor data streaming.

## Purpose
- **Deploy** Apache Pulsar on Kubernetes (EKS) using Helm
- **Configure** for high-performance IoT data ingestion
- **Provide** durable message storage with topic partitioning
- **Handle** 30,000+ messages/second with low latency

## Key Components

### 1. Helm Deployment
**Location:** `helm/pulsar/`

Contains the official Apache Pulsar Helm chart with 326 files including:
- Chart templates for all Pulsar components
- Configuration files for brokers, bookies, ZooKeeper
- Service definitions and ingress configurations
- Custom resource definitions

### 2. Configuration File: pulsar-values.yaml
**Purpose:** Custom Helm values for optimized IoT workload

**Key Configurations:**
```yaml
# Resource allocation
broker:
  replicas: 3
  resources:
    requests:
      cpu: 2000m
      memory: 4Gi
    limits:
      cpu: 4000m
      memory: 8Gi

# Storage configuration
bookkeeper:
  replicas: 3
  journal:
    storage: nvme-ssd
  ledger:
    storage: nvme-ssd

# Performance tuning
zookeeper:
  replicas: 3
  resources:
    requests:
      cpu: 500m
      memory: 2Gi
```

**Optimizations:**
- **NVMe Storage:** Uses local NVMe SSDs for ultra-low latency
- **Resource Limits:** Sized for 30K+ msgs/sec throughput
- **Replication:** 3 replicas for high availability
- **Topic Partitioning:** Supports partitioned topics for parallel consumption

### 3. Performance Testing: pulsar-sensor-perf
**Purpose:** High-performance IoT data generator written in Go/Java

**Key Features:**
- Device ID range control (min/max device IDs)
- Configurable message rate (messages/second)
- Device type distribution
- AVRO encoding support
- Realistic sensor data generation

**Usage:**
```bash
./pulsar-sensor-perf iot-produce \
  --device-id-min 1 \
  --device-id-max 1000 \
  --rate 250000 \
  --topics persistent://public/default/iot-sensor-data \
  --service-url pulsar://localhost:6650
```

**Data Generation:**
- Distributes message rate evenly across all device IDs
- Generates 25+ fields per message matching ClickHouse schema
- Supports AVRO serialization for compact message size
- Can sustain 250K+ messages/second per producer instance

### 4. Deployment Scripts

#### deploy.sh
**Purpose:** Automated Pulsar deployment to EKS

**Steps:**
1. Creates `pulsar` namespace
2. Installs EBS CSI driver for persistent volumes
3. Sets up NVMe storage via DaemonSet
4. Deploys Pulsar using Helm with custom values
5. Waits for all components to be ready
6. Creates IoT sensor data topic

**Components Deployed:**
- **ZooKeeper:** Coordination service (3 nodes)
- **BookKeeper:** Persistent message storage (3 bookies)
- **Broker:** Message routing and serving (3 brokers)
- **Proxy:** Load balancing and external access
- **Toolset:** Admin utilities pod

#### nvme-setup-daemonset.yaml
**Purpose:** Configures local NVMe storage on EKS nodes

**What it does:**
- Runs on all Pulsar nodes
- Formats and mounts NVMe SSDs
- Creates mount points for BookKeeper journal and ledger storage
- Ensures optimal I/O performance

### 5. Testing and Validation

#### test-avro-producer.sh
**Purpose:** Test AVRO message production to Pulsar

**Tests:**
- AVRO schema validation
- Message serialization
- Connection to Pulsar broker
- Topic creation and message publishing

#### test-iot-producer.sh
**Purpose:** End-to-end IoT producer testing

**Validates:**
- Device ID range generation
- Message rate control
- Field population
- Network throughput

#### test-avro-consumer.java
**Purpose:** Validates AVRO message consumption

**Tests:**
- AVRO deserialization
- Schema compatibility
- Message ordering
- Subscription management

### 6. Documentation

#### IOT_PRODUCER_USAGE.md
Complete guide for using the IoT producer:
- Command-line options
- Device ID distribution strategies
- Rate limiting configuration
- Performance tuning tips

#### AVRO_TESTING_GUIDE.md
AVRO-specific testing procedures:
- Schema evolution testing
- Compatibility checks
- Performance benchmarks
- Troubleshooting guide

## Architecture

### Pulsar Cluster Components
```
┌─────────────────────────────────────────────────────────┐
│                    Pulsar Cluster                       │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌─────────────┐    ┌─────────────┐   ┌────────────┐  │
│  │  ZooKeeper  │←──→│   Broker    │←─→│   Proxy    │  │
│  │  (3 nodes)  │    │  (3 nodes)  │   │ (external) │  │
│  └─────────────┘    └──────┬──────┘   └────────────┘  │
│                             │                           │
│                             ↓                           │
│                     ┌──────────────┐                    │
│                     │  BookKeeper  │                    │
│                     │  (3 bookies) │                    │
│                     │  NVMe Storage│                    │
│                     └──────────────┘                    │
└─────────────────────────────────────────────────────────┘
```

### Data Flow
```
IoT Producer → Pulsar Proxy → Broker → BookKeeper (persistence)
                                  ↓
                            Flink Consumer
```

## Performance Characteristics

### Throughput
- **Write:** 30,000-250,000 messages/second per topic
- **Read:** Parallel consumption via Flink (multiple task managers)
- **Latency:** <10ms p99 with NVMe storage

### Storage
- **Journal:** NVMe SSD for write-ahead log (low latency writes)
- **Ledger:** NVMe SSD for message storage (high-throughput reads)
- **Retention:** Configurable per topic (default: 7 days)

### Scalability
- **Horizontal:** Add more brokers for more topics/connections
- **Vertical:** Increase broker resources for higher per-broker throughput
- **Partitioning:** Topic partitions for parallel producer/consumer

## Topic Configuration

### IoT Sensor Data Topic
```
Name: persistent://public/default/iot-sensor-data
Type: Partitioned (configurable)
Replication: 3
Retention: 7 days
Compression: LZ4
Schema: AVRO (SensorData.avsc)
```

### Message Format (AVRO)
```
{
  "sensorId": int,
  "sensorType": int,
  "temperature": double,
  "humidity": double,
  "pressure": double,
  "batteryLevel": double,
  "status": int,
  "timestamp": long
}
```

## Monitoring

### Topic Statistics
```bash
kubectl exec -n pulsar pulsar-toolset-0 -- \
  bin/pulsar-admin topics stats persistent://public/default/iot-sensor-data
```

**Metrics shown:**
- Message rate in/out
- Storage size
- Subscription backlog
- Consumer lag

### Broker Metrics
```bash
kubectl exec -n pulsar pulsar-broker-0 -- \
  curl http://localhost:8080/metrics/
```

**Key metrics:**
- CPU and memory usage
- Message throughput
- Connection count
- BookKeeper operations

### Storage Usage
```bash
kubectl exec -n pulsar bookie-0 -- df -h /pulsar/data
```

## Common Operations

### Create Partitioned Topic
```bash
kubectl exec -n pulsar pulsar-toolset-0 -- \
  bin/pulsar-admin topics create-partitioned-topic \
  persistent://public/default/iot-sensor-data \
  --partitions 10
```

### Set Message Retention
```bash
kubectl exec -n pulsar pulsar-toolset-0 -- \
  bin/pulsar-admin namespaces set-retention public/default \
  --size 100G --time 7d
```

### View Topic Backlog
```bash
kubectl exec -n pulsar pulsar-toolset-0 -- \
  bin/pulsar-admin topics stats-internal \
  persistent://public/default/iot-sensor-data
```

### Consume Messages (Testing)
```bash
kubectl exec -n pulsar pulsar-toolset-0 -- \
  bin/pulsar-client consume \
  persistent://public/default/iot-sensor-data \
  -s test-sub -n 10
```

## Deployment Steps

### 1. Provision Infrastructure
```bash
cd ../
terraform apply -var-file=terraform.tfvars.pulsar
```
Creates EKS node groups for Pulsar components

### 2. Deploy Pulsar
```bash
cd pulsar-load
./deploy.sh
```
Installs all Pulsar components

### 3. Verify Deployment
```bash
kubectl get pods -n pulsar
kubectl get pvc -n pulsar
```
All pods should be Running, PVCs should be Bound

### 4. Test Producer
```bash
./test-iot-producer.sh
```
Validates producer can write to Pulsar

## Storage Configuration

### NVMe Setup
- **Path:** `/mnt/nvme/pulsar`
- **Journal:** `/mnt/nvme/pulsar/journal`
- **Ledger:** `/mnt/nvme/pulsar/ledgers`
- **Format:** XFS filesystem
- **Permissions:** pulsar user (UID 10000)

### Persistent Volumes
- **ZooKeeper:** 20Gi per node (EBS gp3)
- **BookKeeper:** 200Gi per bookie (local NVMe)
- **Broker:** Stateless (no persistent storage)

## Troubleshooting

### Pods Not Starting
**Check node groups:**
```bash
kubectl get nodes -l workload=pulsar
```
Ensure Pulsar nodes are available

**Check PVC binding:**
```bash
kubectl get pvc -n pulsar
```
All PVCs should be Bound

### Low Throughput
**Check NVMe mounts:**
```bash
kubectl exec -n pulsar bookie-0 -- df -h | grep nvme
```

**Check broker logs:**
```bash
kubectl logs -n pulsar pulsar-broker-0
```

### Connection Failures
**Verify services:**
```bash
kubectl get svc -n pulsar
```

**Test connectivity:**
```bash
kubectl exec -n pulsar pulsar-toolset-0 -- \
  bin/pulsar-admin brokers list pulsar-cluster
```

## Dependencies
- **Kubernetes:** EKS 1.27+
- **Helm:** v3.x
- **EBS CSI Driver:** For persistent volumes
- **Local NVMe:** For high-performance storage
- **Terraform:** Infrastructure provisioning

## Summary
The pulsar-load folder provides:
1. **Complete deployment** of Apache Pulsar on Kubernetes
2. **Optimized configuration** for IoT streaming workloads
3. **Performance testing tools** for validation
4. **Production-ready** setup with HA and persistence
5. **Monitoring and operations** utilities

