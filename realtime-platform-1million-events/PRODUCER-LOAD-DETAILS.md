# Producer Load - Detailed Documentation

## Overview
The `producer-load` folder contains a high-throughput Java-based IoT data producer that generates realistic sensor data and publishes it to Apache Pulsar using AVRO serialization.

## Purpose
- **Generate** realistic IoT sensor data at scale (1000-5000 msgs/sec per pod)
- **Publish** to Apache Pulsar with AVRO encoding
- **Distribute** messages across 17,000 unique device IDs
- **Scale** horizontally across multiple Kubernetes pods

## Build Approach

### Multi-Stage Docker Build
This producer uses a **multi-stage Docker build** that:

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
- ✅ Automatic dependency resolution

**Required Files in Repository:**
- `IoTPerformanceProducer.java` - Custom producer implementation
- `pulsar-sensor-perf` - Wrapper script
- `Dockerfile.perf` - Multi-stage build definition
- `entrypoint.sh` - Device ID distribution logic
- `BUILD-APPROACH.md` - Detailed build documentation

See `BUILD-APPROACH.md` for complete build details and troubleshooting.

## Key Components

### 1. Data Model

#### SensorData.java
**Location:** `src/main/java/com/iot/pipeline/model/SensorData.java`

**Purpose:** Java POJO representing IoT sensor readings

**Fields (25+):**
```java
// Device identifiers
String device_id          // e.g., "dev-0012345"
String device_type        // e.g., "temperature_sensor"
String customer_id        // e.g., "cust-005432"
String site_id           // e.g., "site-00123"

// Location data
double latitude          // GPS coordinates
double longitude
double altitude          // meters above sea level

// Timestamp
long time               // milliseconds since epoch

// Sensor readings
double temperature      // Celsius (15-40°C)
double humidity        // Percentage (20-90%)
double pressure        // hPa (980-1040)
double co2_level       // ppm (400-2000)
double noise_level     // dB (30-90)
double light_level     // lux (0-10000)
int motion_detected    // 0 or 1

// Device metrics
double battery_level     // Percentage (0-100%)
double signal_strength   // dBm (-90 to -30)
double memory_usage      // Percentage (20-80%)
double cpu_usage        // Percentage (10-70%)

// Status
int status              // 1=online, 2=offline, 3=maintenance, 4=error
int error_count         // cumulative errors

// Network metrics
long packets_sent
long packets_received
long bytes_sent
long bytes_received
```

**Device Pool Configuration:**
- **Device IDs:** 17,000 unique devices (dev-0000000 to dev-0016999)
- **Customers:** 10,000 unique customers (cust-000000 to cust-009999)
- **Sites:** 1,000 unique sites (site-00000 to site-00999)
- **Device Types:** 20 types (temperature_sensor, humidity_sensor, pressure_sensor, motion_sensor, light_sensor, co2_sensor, noise_sensor, multisensor, etc.)

**Realistic Data Ranges:**
- Temperature: 15-40°C (with occasional outliers for alerts)
- Humidity: 20-90% (with high values for alert testing)
- Battery: 10-100% (with low values for alert testing)
- Pressure: 980-1040 hPa (normal atmospheric range)
- CO2: 400-2000 ppm (indoor air quality range)
- Noise: 30-90 dB (ambient to loud)
- Light: 0-10,000 lux (dark to bright sunlight)

### 2. Producer Implementation

#### IoTDataProducer.java
**Location:** `src/main/java/com/iot/pipeline/producer/IoTDataProducer.java`

**Purpose:** Main producer class that generates and sends data to Pulsar

**Key Features:**

**a) AVRO Serialization**
- Uses Apache AVRO schema for compact binary encoding
- Reduces message size by ~60% compared to JSON
- Schema stored in `src/main/resources/avro/SensorData.avsc`
- Compatible with Flink consumer's AVRO deserialization

**b) Rate Control**
```java
MESSAGES_PER_SECOND (configurable via env var)
Default: 1000 msg/sec per pod
Max tested: 5000 msg/sec per pod
```

**Rate Limiting Strategy:**
- Token bucket algorithm for smooth rate distribution
- Prevents bursts that could overwhelm downstream systems
- Configurable via environment variable

**c) Pulsar Integration**
```java
PulsarClient client = PulsarClient.builder()
    .serviceUrl(pulsarUrl)
    .build();

Producer<byte[]> producer = client.newProducer()
    .topic(topic)
    .compressionType(CompressionType.LZ4)
    .batchingEnabled(true)
    .sendTimeout(10, TimeUnit.SECONDS)
    .create();
```

**Connection Settings:**
- **Batching:** Enabled for throughput optimization
- **Compression:** LZ4 for fast compression/decompression
- **Timeout:** 10-second send timeout
- **Retry:** Automatic retry on transient failures

**d) Data Generation Logic**
```java
// Random device selection from pool
int deviceIndex = random.nextInt(DEVICE_POOL_SIZE);
String deviceId = String.format("dev-%07d", deviceIndex);

// Customer and site derived from device for locality
String customerId = String.format("cust-%06d", deviceIndex / 10);
String siteId = String.format("site-%05d", deviceIndex / 100);

// Random device type
String deviceType = DEVICE_TYPES[random.nextInt(DEVICE_TYPES.length)];

// Realistic sensor readings with controlled randomness
double temperature = 20.0 + (random.nextDouble() * 20.0);  // 20-40°C
double humidity = 30.0 + (random.nextDouble() * 50.0);     // 30-80%
```

**Alert Conditions:**
- 5% chance of high temperature (>35°C) → triggers has_alert
- 3% chance of high humidity (>80%) → triggers has_alert
- 2% chance of low battery (<20%) → triggers has_alert

**e) Monitoring & Logging**
```java
// Periodic stats logging (every 10 seconds)
- Messages sent count
- Current rate (msgs/sec)
- Errors encountered
- Latency percentiles
```

### 3. Deployment Configuration

#### Dockerfile
**Purpose:** Multi-stage Docker build for optimized image

**Stage 1: Build**
```dockerfile
FROM maven:3.8-openjdk-11 AS builder
COPY pom.xml .
COPY src ./src
RUN mvn clean package -DskipTests
```

**Stage 2: Runtime**
```dockerfile
FROM openjdk:11-jre-slim
COPY --from=builder /app/target/*.jar /app/producer.jar
ENTRYPOINT ["java", "-jar", "/app/producer.jar"]
```

**Benefits:**
- Smaller final image (~150MB vs ~600MB)
- No build tools in production image
- Faster deployment and scaling

#### producer-deployment.yaml
**Purpose:** Kubernetes deployment manifest

**Configuration:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: iot-producer
  namespace: iot-pipeline
spec:
  replicas: 3  # 3 pods = 3000 msg/sec total
  
  template:
    spec:
      containers:
      - name: producer
        image: <ECR_URL>/bench-low-infra-producer:latest
        
        env:
        - name: PULSAR_URL
          value: "pulsar://pulsar-proxy.pulsar.svc.cluster.local:6650"
        - name: PULSAR_TOPIC
          value: "persistent://public/default/iot-sensor-data"
        - name: MESSAGES_PER_SECOND
          value: "1000"
        - name: JAVA_OPTS
          value: "-Xms512m -Xmx1024m"
        
        resources:
          requests:
            cpu: 500m
            memory: 1Gi
          limits:
            cpu: 1000m
            memory: 1.5Gi
      
      nodeSelector:
        workload: bench-producer  # Runs on dedicated producer nodes
```

**Scaling Options:**

**Horizontal Scaling:**
```bash
kubectl scale deployment iot-producer -n iot-pipeline --replicas=5
# 5 pods × 1000 msg/sec = 5000 msg/sec total
```

**Vertical Scaling:**
```yaml
env:
- name: MESSAGES_PER_SECOND
  value: "2000"  # Double rate per pod
# 3 pods × 2000 msg/sec = 6000 msg/sec total
```

#### producer-deployment-distributed.yaml
**Purpose:** StatefulSet for distributed deployment with unique device ranges

**Key Difference:**
- Uses StatefulSet instead of Deployment
- Each pod gets unique device ID range
- Prevents duplicate device IDs across pods
- Better for testing specific device behaviors

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: iot-producer
spec:
  replicas: 3
  template:
    spec:
      containers:
      - name: producer
        env:
        - name: POD_INDEX
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: DEVICE_ID_OFFSET
          value: "$(POD_INDEX * 33333)"  # Each pod gets 33,333 devices
```

#### producer-deployment-perf.yaml
**Purpose:** High-performance deployment for maximum throughput testing

**Optimizations:**
- Higher resource limits (2 CPU, 2Gi RAM)
- Increased message rate (5000 msg/sec)
- JVM tuning for low GC overhead
- Dedicated high-performance nodes

### 4. Build and Deployment Scripts

#### build-and-push.sh
**Purpose:** Automated build and ECR push

**Steps:**
1. Authenticate to AWS ECR
2. Create ECR repository if not exists
3. Build JAR with Maven
4. Build Docker image for linux/amd64 (x86_64)
5. Tag image with `latest`
6. Push to ECR
7. Update deployment YAML with image URL

**Usage:**
```bash
./build-and-push.sh
```

**Build Time:** ~5-10 minutes (first time), ~2-3 minutes (cached)

#### build-and-push-perf.sh
**Purpose:** Build optimized performance image

**Differences:**
- Uses Dockerfile.perf with additional JVM tuning
- Enables JVM performance flags
- Larger heap size configuration

#### deploy.sh
**Purpose:** Deploy producer to Kubernetes

**Steps:**
1. Configure kubectl for EKS cluster
2. Create `iot-pipeline` namespace
3. Apply producer deployment
4. Wait for pods to be Ready
5. Display pod status
6. Show initial logs
7. Print monitoring commands

**Usage:**
```bash
./deploy.sh
```

#### deploy-with-partitions.sh
**Purpose:** Deploy with partitioned Pulsar topic support

**Additional Steps:**
- Creates partitioned topic (10 partitions)
- Configures producer for partition routing
- Better for very high throughput scenarios

### 5. Testing and Validation

#### test-avro-local.sh
**Purpose:** Local AVRO serialization testing

**Tests:**
- AVRO schema loading
- Message serialization
- Deserialization round-trip
- Schema compatibility

**Usage:**
```bash
./test-avro-local.sh
```

#### simple-pulsar-consumer.py
**Purpose:** Simple Python consumer for validation

**Features:**
- Subscribes to IoT topic
- Prints received messages
- Validates message format
- Shows consumption rate

**Usage:**
```bash
python3 simple-pulsar-consumer.py
```

**Validates:**
- Producer is sending messages
- Messages are valid AVRO
- Field values are in expected ranges
- No message loss

### 6. Documentation

#### AVRO_DOCKER_SETUP.md
Complete guide for AVRO and Docker setup:
- AVRO schema definition
- Schema evolution strategies
- Docker build process
- Troubleshooting AVRO issues

#### DEVICE_ID_DISTRIBUTION_GUIDE.md
Device ID management strategies:
- How device IDs are distributed
- Preventing duplicates in distributed deployments
- Customer and site assignment logic
- Load balancing considerations

## Data Flow

```
┌──────────────────┐     ┌──────────────┐     ┌─────────────┐
│  IoTDataProducer │ ──→ │    Pulsar    │ ──→ │    Flink    │
│   (Java/AVRO)    │     │ (partitioned)│     │  Consumer   │
└──────────────────┘     └──────────────┘     └─────────────┘
  100K devices             Topic buffer           Aggregation
  1K-5K msg/sec           LZ4 compression        → ClickHouse
  AVRO encoded            Persistent storage
```

## Performance Characteristics

### Throughput
- **Per Pod:** 1000-5000 messages/second (configurable)
- **3-Pod Default:** 3000 messages/second
- **10-Pod Max:** 50,000 messages/second
- **Message Size:** ~200 bytes (AVRO), ~500 bytes (JSON)

### Resource Usage (per pod at 1000 msg/sec)
- **CPU:** ~500m (0.5 cores)
- **Memory:** ~800Mi
- **Network:** ~2-5 MB/sec
- **Disk:** None (stateless)

### Scaling Limits
- **Max tested:** 10 pods × 5000 msg/sec = 50K msg/sec
- **Bottleneck:** Network bandwidth to Pulsar
- **Recommendation:** Scale Pulsar brokers proportionally

## Monitoring

### View Producer Logs
```bash
kubectl logs -f -n iot-pipeline -l app=iot-producer
```

### Check Pod Status
```bash
kubectl get pods -n iot-pipeline -o wide
```

### Monitor Message Rate
```bash
kubectl logs -n iot-pipeline -l app=iot-producer | grep "Sent"
```

### Check Pulsar Topic
```bash
kubectl exec -n pulsar pulsar-toolset-0 -- \
  bin/pulsar-admin topics stats persistent://public/default/iot-sensor-data
```

## Common Operations

### Scale Producers
```bash
kubectl scale deployment iot-producer -n iot-pipeline --replicas=5
```

### Update Message Rate
```bash
kubectl set env deployment/iot-producer -n iot-pipeline MESSAGES_PER_SECOND=2000
```

### Restart Producers
```bash
kubectl rollout restart deployment/iot-producer -n iot-pipeline
```

### Delete Deployment
```bash
kubectl delete deployment iot-producer -n iot-pipeline
```

## Troubleshooting

### Pods Not Starting
**Check nodes:**
```bash
kubectl get nodes -l workload=bench-producer
```

**Check image:**
```bash
kubectl describe pod -n iot-pipeline <pod-name> | grep Image
```

### Low Throughput
**Check CPU throttling:**
```bash
kubectl top pods -n iot-pipeline
```

**Increase resources:**
```yaml
resources:
  limits:
    cpu: 2000m
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

## Dependencies
- **Java:** OpenJDK 11+
- **Maven:** 3.8+ (for building)
- **Pulsar Client:** v2.10+
- **AVRO:** Apache AVRO 1.11+
- **Kubernetes:** For deployment
- **Docker:** For containerization

## Summary
The producer-load folder provides:
1. **High-throughput IoT data generator** with realistic sensor readings
2. **AVRO serialization** for efficient message encoding
3. **Scalable deployment** across multiple Kubernetes pods
4. **Configurable message rates** from 1K to 50K msg/sec
5. **Production-ready** with monitoring, testing, and fault tolerance
6. **100,000 unique devices** with proper distribution across customers and sites

