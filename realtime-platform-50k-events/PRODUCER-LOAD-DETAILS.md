# Producer Load - Detailed Documentation (50K Messages/Second)

## Overview
The `producer-load` folder contains a cost-optimized event data producer that generates realistic event data and publishes it to Apache Pulsar using AVRO serialization. This version is configured for **up to 50,000 messages per second** using smaller, cost-effective t3 instances.

## Purpose
- **Generate** realistic event stream data at moderate scale (500-1K msg/sec per pod)
- **Publish** to Apache Pulsar with AVRO encoding
- **Distribute** messages across 17,000 unique event sources
- **Scale** horizontally across multiple Kubernetes pods (t3.medium instances)
- **Cost-optimize** for moderate workloads (~$15-50/month for producer nodes)

## Build Approach

### Multi-Stage Docker Build
This producer uses the **same multi-stage Docker build** as the 1M MPS setup:

1. **Stage 1 (Builder):**
   - Downloads Apache Pulsar 4.1.1 source code (~150MB)
   - Copies `IoTPerformanceProducer.java` into the source tree
   - Builds only the `pulsar-testclient` module with Maven
   - Generates `pulsar-testclient.jar` and copies all dependencies (~365 JARs)
   - **Build time:** 10-15 minutes (first build), 2-3 minutes (cached)

2. **Stage 2 (Runtime):**
   - Lightweight JRE Alpine image
   - Copies only built artifacts from Stage 1
   - Includes `pulsar-sensor-perf` wrapper script
   - **Final image size:** ~721MB

**Benefits:**
- ✅ No JAR files in Git repository (clean codebase)
- ✅ Reproducible builds from official Pulsar source
- ✅ Standard Maven best practices
- ✅ Easy Pulsar version updates

**Required Files in Repository:**
- `IoTPerformanceProducer.java` - Custom producer implementation
- `pulsar-sensor-perf` - Wrapper script
- `Dockerfile.perf` - Multi-stage build definition

## Key Differences from 1M Setup

| Aspect | 50K Setup | 1M Setup |
|--------|-----------|----------|
| Instance Type | t3.medium | c5.4xlarge |
| vCPU per pod | 2 | 16 |
| RAM per pod | 4 GB | 32 GB |
| Rate per pod | 500-1K msg/sec | 1K-5K msg/sec |
| Event sources | 17,000 unique IDs | 17,000 unique IDs |
| Pod count | 1-3 (default: 1) | 3-16 (default: 3) |
| Total capacity | Up to 3K msg/sec | Up to 50K msg/sec |
| Monthly cost | ~$15-50 | ~$367 |

## Data Model

### Event Sources Pool
- **17,000** unique event source IDs (source-0000000 to source-0016999)
- **1,000** customers (cust-000000 to cust-000999)
- **100** sites (site-00000 to site-00099)
- **20** event types

**Fields Generated (25+ per record):**
- Event identifiers: source_id, event_type, customer_id, site_id
- Location: latitude, longitude, altitude
- Timestamp: time (DateTime64(3))
- Metrics: temperature, humidity, pressure, co2_level, noise_level, light_level, motion_detected
- Device metrics: battery_level, signal_strength, memory_usage, cpu_usage
- Status: status (1=online, 2=offline, 3=maintenance, 4=error), error_count
- Network metrics: packets_sent, packets_received, bytes_sent, bytes_received

## Key Files

### EventDataProducer.java
**Purpose:** Main producer class generating event data

**Configuration:**
```java
// Rate control (configurable via env var)
MESSAGES_PER_SECOND = 1000  // Default: 1000 msg/sec
EVENT_SOURCE_POOL_SIZE = 10000  // 10K unique sources

// Pulsar connection
PulsarClient client = PulsarClient.builder()
    .serviceUrl(pulsarUrl)  // pulsar://pulsar-proxy.pulsar.svc.cluster.local:6650
    .build();

// AVRO serialization for compact messages
```

**Rate Limiting Strategy:**
- Token bucket algorithm
- Smooth distribution over time
- Prevents downstream overload
- Configurable per pod

**Data Generation:**
```java
// Random event source from pool (10K sources)
int sourceIndex = random.nextInt(10000);
String sourceId = String.format("source-%07d", sourceIndex);

// Derived customer and site for locality
String customerId = String.format("cust-%06d", sourceIndex / 10);
String siteId = String.format("site-%05d", sourceIndex / 100);

// Realistic metrics with controlled randomness
double temperature = 20.0 + (random.nextDouble() * 20.0);  // 20-40°C
double humidity = 30.0 + (random.nextDouble() * 50.0);     // 30-80%
```

## Deployment Configuration

### Dockerfile
Multi-stage build optimized for smaller image size:

```dockerfile
# Stage 1: Build with Maven
FROM maven:3.8-openjdk-11 AS builder
COPY pom.xml .
COPY src ./src
RUN mvn clean package -DskipTests

# Stage 2: Runtime (smaller image)
FROM openjdk:11-jre-slim
COPY --from=builder /app/target/*.jar /app/producer.jar
ENTRYPOINT ["java", "-Xms256m", "-Xmx512m", "-jar", "/app/producer.jar"]
```

**Optimizations:**
- Smaller heap size (256m-512m vs 512m-1024m)
- JRE-slim base image
- Final image: ~120MB

### producer-deployment.yaml
**Purpose:** Kubernetes deployment for cost-optimized setup

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: event-producer
  namespace: iot-pipeline
spec:
  replicas: 1  # Start with 1 pod = 1K msg/sec
  
  template:
    spec:
      containers:
      - name: producer
        image: <ECR_URL>/bench-low-infra-producer:latest
        
        env:
        - name: PULSAR_URL
          value: "pulsar://pulsar-proxy.pulsar.svc.cluster.local:6650"
        - name: PULSAR_TOPIC
          value: "persistent://public/default/event-stream-data"
        - name: MESSAGES_PER_SECOND
          value: "1000"
        - name: EVENT_SOURCE_COUNT
          value: "10000"
        - name: JAVA_OPTS
          value: "-Xms256m -Xmx512m"
        
        resources:
          requests:
            cpu: 250m      # Reduced from 500m
            memory: 512Mi  # Reduced from 1Gi
          limits:
            cpu: 500m      # Reduced from 1000m
            memory: 768Mi  # Reduced from 1.5Gi
      
      nodeSelector:
        workload: producer  # Runs on t3.medium nodes
```

**Scaling Options:**

**Horizontal Scaling (Recommended):**
```bash
# Scale to 10K msg/sec
kubectl scale deployment event-producer -n iot-pipeline --replicas=10

# Scale to 30K msg/sec
kubectl scale deployment event-producer -n iot-pipeline --replicas=30

# Scale to 50K msg/sec
kubectl scale deployment event-producer -n iot-pipeline --replicas=50
```

**Vertical Scaling:**
```bash
# Increase rate per pod (requires more CPU)
kubectl set env deployment/event-producer -n iot-pipeline MESSAGES_PER_SECOND=2000
```

## Performance Characteristics

### Throughput
- **Per Pod:** 500-1,000 messages/second (configurable)
- **1-Pod Default:** 1,000 messages/second
- **10-Pod Setup:** 10,000 messages/second
- **50-Pod Max:** 50,000 messages/second
- **Message Size:** ~200 bytes (AVRO), ~500 bytes (JSON)

### Resource Usage (per pod at 1000 msg/sec)
- **CPU:** ~250m (0.25 cores) - burstable with t3
- **Memory:** ~400Mi
- **Network:** ~1-2 MB/sec
- **Disk:** None (stateless)

### Instance Type: t3.medium
- **vCPU:** 2 (burstable)
- **RAM:** 4 GB
- **Network:** Up to 5 Gbps
- **Cost:** ~$30/month on-demand (~$12/month spot)
- **Pods per node:** 2-3 producer pods
- **Total throughput per node:** 2K-3K msg/sec

### Scaling Limits
- **Max tested:** 50 pods × 1000 msg/sec = 50K msg/sec
- **Bottleneck:** Pulsar broker capacity
- **Recommendation:** Scale Pulsar proportionally

## Build and Deployment Scripts

### build-and-push.sh
**Purpose:** Build and push to ECR

```bash
#!/bin/bash

# Authenticate to AWS ECR
aws ecr get-login-password --region us-west-2 | \
  docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.us-west-2.amazonaws.com

# Build JAR
mvn clean package -DskipTests

# Build Docker image (cost-optimized)
docker build -t bench-low-infra-producer:latest .

# Tag and push
docker tag bench-low-infra-producer:latest \
  <ACCOUNT_ID>.dkr.ecr.us-west-2.amazonaws.com/bench-low-infra-producer:latest
  
docker push <ACCOUNT_ID>.dkr.ecr.us-west-2.amazonaws.com/bench-low-infra-producer:latest
```

### deploy.sh
**Purpose:** Deploy to Kubernetes

```bash
#!/bin/bash

# Configure kubectl
aws eks update-kubeconfig --region us-west-2 --name bench-low-infra

# Create namespace
kubectl create namespace iot-pipeline --dry-run=client -o yaml | kubectl apply -f -

# Deploy producer
kubectl apply -f producer-deployment.yaml

# Wait for pods
kubectl wait --for=condition=ready pod -l app=event-producer -n iot-pipeline --timeout=300s

# Show status
kubectl get pods -n iot-pipeline
kubectl logs -f -n iot-pipeline -l app=event-producer --tail=20
```

## Use Cases by Domain

### E-Commerce (10K events/sec)
```yaml
env:
- name: EVENT_TYPE
  value: "order_events"
- name: MESSAGES_PER_SECOND
  value: "1000"

# Deploy 10 pods for 10K events/sec
replicas: 10
```

**Generated events:**
- Order placed, updated, cancelled
- Inventory changes
- Cart actions
- Price updates

### Finance (30K events/sec)
```yaml
env:
- name: EVENT_TYPE
  value: "transaction_events"
- name: MESSAGES_PER_SECOND
  value: "1000"

# Deploy 30 pods for 30K events/sec
replicas: 30
```

**Generated events:**
- Payment transactions
- Account updates
- Market data updates
- Fraud alerts

### IoT (50K events/sec)
```yaml
env:
- name: EVENT_TYPE
  value: "sensor_telemetry"
- name: MESSAGES_PER_SECOND
  value: "1000"

# Deploy 50 pods for 50K events/sec
replicas: 50
```

**Generated events:**
- Sensor readings
- Device status
- Alerts and alarms
- Diagnostic data

## Monitoring

### View Producer Logs
```bash
kubectl logs -f -n iot-pipeline -l app=event-producer
```

**Expected output:**
```
Sent 1000 messages in last second
Current rate: 1000 msg/sec
Total sent: 60000 messages
```

### Check Pod Status
```bash
kubectl get pods -n iot-pipeline -o wide
```

### Monitor Resource Usage
```bash
# Check CPU/Memory usage
kubectl top pods -n iot-pipeline

# Check node usage
kubectl top nodes -l workload=producer
```

### Check Pulsar Topic
```bash
kubectl exec -n pulsar pulsar-toolset-0 -- \
  bin/pulsar-admin topics stats persistent://public/default/event-stream-data
```

## Common Operations

### Scale Producers
```bash
# Scale to 5 pods (5K msg/sec)
kubectl scale deployment event-producer -n iot-pipeline --replicas=5

# Scale to 20 pods (20K msg/sec)
kubectl scale deployment event-producer -n iot-pipeline --replicas=20
```

### Update Message Rate
```bash
# Increase rate per pod
kubectl set env deployment/event-producer -n iot-pipeline \
  MESSAGES_PER_SECOND=2000
```

### Change Event Source Count
```bash
# Use only 5K event sources
kubectl set env deployment/event-producer -n iot-pipeline \
  EVENT_SOURCE_COUNT=5000
```

### Restart Producers
```bash
kubectl rollout restart deployment/event-producer -n iot-pipeline
```

### Delete Deployment
```bash
kubectl delete deployment event-producer -n iot-pipeline
```

## Troubleshooting

### Pods Not Starting

**Check nodes:**
```bash
kubectl get nodes -l workload=producer
```

**If no nodes, scale up producer node group:**
```bash
# Update terraform.tfvars
producer_desired_size = 2

# Apply
terraform apply
```

### Low Throughput

**Check CPU throttling:**
```bash
kubectl top pods -n iot-pipeline
```

**Solution: Increase resources or scale horizontally:**
```bash
# Horizontal scaling (preferred)
kubectl scale deployment event-producer -n iot-pipeline --replicas=3
```

### Connection Errors

**Verify Pulsar service:**
```bash
kubectl get svc -n pulsar pulsar-proxy
```

**Test connectivity:**
```bash
kubectl exec -n iot-pipeline <producer-pod> -- \
  nc -zv pulsar-proxy.pulsar.svc.cluster.local 6650
```

## Cost Analysis

### Per-Pod Cost (t3.medium)
- **On-Demand:** ~$30/month per node (2-3 pods per node)
- **Spot Instance:** ~$12/month per node (60% savings)
- **Cost per msg/sec:** ~$0.01/month per msg/sec (spot)

### Scaling Cost Examples

**10K msg/sec (10 pods, 4 nodes):**
- On-Demand: ~$120/month
- Spot: ~$48/month

**30K msg/sec (30 pods, 10 nodes):**
- On-Demand: ~$300/month
- Spot: ~$120/month

**50K msg/sec (50 pods, 17 nodes):**
- On-Demand: ~$510/month
- Spot: ~$204/month

## Summary

The producer-load folder for 50K setup provides:

1. **Cost-optimized event generator** with t3.medium instances
2. **Moderate throughput** (500-1K msg/sec per pod)
3. **Scalable deployment** (1-50 pods for 1K-50K msg/sec)
4. **10,000 unique event sources** with proper distribution
5. **Multi-domain support** (e-commerce, finance, IoT, gaming, logistics)
6. **Budget-friendly** (~$50-200/month depending on scale)
7. **Easy scaling** (horizontal preferred)
8. **Production-ready** with monitoring and fault tolerance

**Perfect for:**
- Development and testing
- Small to medium workloads
- Cost-conscious deployments
- Growing platforms
- Proof of concept projects

