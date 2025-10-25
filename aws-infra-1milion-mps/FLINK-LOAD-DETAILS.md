# Flink Load - Detailed Documentation

## Overview
The `flink-load` folder contains the Apache Flink streaming job that consumes IoT sensor data from Apache Pulsar, aggregates it in 1-minute windows, and writes the results to ClickHouse.

## Purpose
- **Consume** IoT sensor data from Pulsar topics (AVRO format)
- **Process & Aggregate** data in real-time using 1-minute tumbling windows per device
- **Write** aggregated data to ClickHouse database
- **Handle** 30,000+ messages/second with fault tolerance

## Key Files

### Core Application: JDBCFlinkConsumer.java
**Location:** `flink-consumer/src/main/java/com/iot/pipeline/flink/JDBCFlinkConsumer.java`

This is the main Flink streaming application with three core components:

#### 1. AVRO Deserialization Schema (Lines 43-85)
```java
AvroSensorDataDeserializationSchema
```
**Purpose:** Converts binary AVRO messages from Pulsar into `SensorRecord` objects.

**Key Features:**
- Loads AVRO schema from JAR resources (`/avro/SensorData.avsc`)
- Uses Apache AVRO's `DatumReader` for binary deserialization
- Converts directly to `SensorRecord` to avoid Kryo serialization issues
- Handles schema validation at runtime

**Data Flow:**
```
Pulsar AVRO Binary → GenericRecord → SensorRecord
```

#### 2. SensorRecord Class (Lines 140-293)
**Purpose:** Data model matching ClickHouse's `benchmark.sensors_local` schema.

**Fields (25 total):**
- **Device Info:** device_id, device_type, customer_id, site_id
- **Location:** latitude, longitude, altitude
- **Sensor Readings:** temperature, humidity, pressure, co2_level, noise_level, light_level, motion_detected
- **Device Metrics:** battery_level, signal_strength, memory_usage, cpu_usage
- **Status:** status (1=online, 2=offline, 3=maintenance, 4=error), error_count
- **Network Metrics:** packets_sent, packets_received, bytes_sent, bytes_received

**Constructor Logic:**
- **From AVRO (Lines 227-276):** Maps AVRO fields to ClickHouse schema
  - Converts integer `sensorId` → string `device_id` (e.g., "sensor_12345")
  - Converts integer `sensorType` → string `device_type` (e.g., 1 → "temperature_sensor")
  - Provides default values for fields not in AVRO schema
  - Derives `site_id` from `sensorId` for distribution across sites

- **From JSON (Lines 171-225):** Backward compatibility for JSON messages
  - Handles both old field names (sensorId) and new names (device_id)
  - Converts string status ("online") to integer status (1)

#### 3. SensorAggregator (Lines 299-545)
**Purpose:** Aggregates sensor readings over 1-minute windows per device.

**Aggregation Strategy:**
- **Groups by:** device_id using `keyBy(record -> record.device_id)`
- **Window:** 1-minute tumbling windows (`TumblingProcessingTimeWindows.of(Time.minutes(1))`)
- **Computes:** min, max, avg for all sensor readings
- **Reduces:** 30,000 msgs/sec → ~500-1,000 aggregated records/min

**Accumulator Tracks:**
- Sum, min, max for temperature, humidity, pressure, CO2, noise, light, battery, signal strength
- Counters for motion detection, errors, status
- Total network metrics (packets, bytes)

**Output:**
- One aggregated record per device per minute
- Contains average sensor readings
- Preserves device metadata (type, customer, site)

#### 4. ClickHouseJDBCSink (Lines 551-713)
**Purpose:** Checkpoint-aware JDBC sink that writes data to ClickHouse.

**Key Features:**
- **Batching:** Accumulates records in batches of 5,000 for throughput
- **Checkpoint Integration:** Flushes batches during Flink checkpoints for exactly-once semantics
- **State Management:** Implements `CheckpointedFunction` to persist batch count
- **Alert Detection:** Logs alerts for high temp (>35°C), high humidity (>80%), low battery (<20%)

**JDBC Insert:**
```sql
INSERT INTO benchmark.sensors_local (
  device_id, device_type, customer_id, site_id,
  latitude, longitude, altitude, time,
  temperature, humidity, pressure, co2_level, noise_level, light_level, motion_detected,
  battery_level, signal_strength, memory_usage, cpu_usage,
  status, error_count,
  packets_sent, packets_received, bytes_sent, bytes_received
) VALUES (?, ?, ?, ?, ?, ?, ?, now(), ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
```

**Checkpoint Behavior:**
- `snapshotState()`: Flushes pending batch before checkpoint completes
- `initializeState()`: Restores batch count after recovery
- Ensures no data loss during failures

### Data Pipeline Flow
```
┌──────────────┐     ┌────────────────┐     ┌──────────────┐     ┌─────────────┐
│ Pulsar Topic │ ──→ │ AVRO Deserial. │ ──→ │  Aggregator  │ ──→ │ ClickHouse  │
│ (AVRO binary)│     │  to SensorRec  │     │ (1-min win.) │     │ JDBC Sink   │
└──────────────┘     └────────────────┘     └──────────────┘     └─────────────┘
   30K msgs/sec          Parallel             Per device_id         Batched writes
                         Processing           ~500-1K/min           5K batch size
```

## Deployment Files

### build-and-push.sh
Builds the Flink job and pushes Docker image to AWS ECR:
- Compiles Java code with Maven
- Creates multi-stage Docker image (linux/amd64)
- Pushes to ECR repository: `bench-low-infra-flink-job`

### Dockerfile
Multi-stage build:
1. **Build stage:** Maven compilation
2. **Runtime stage:** Flink base image + compiled JAR + dependencies

### flink-job-deployment.yaml
Kubernetes FlinkDeployment Custom Resource:
- **JobManager:** 1 replica, 2GB RAM, 1 CPU
- **TaskManager:** 2 replicas, 2GB RAM each, 2 task slots per TM
- **Environment Variables:**
  - `PULSAR_URL`: Pulsar service URL
  - `PULSAR_TOPIC`: IoT sensor data topic
  - `CLICKHOUSE_URL`: ClickHouse JDBC connection string
- **Checkpointing:** 1-minute intervals, exactly-once mode, RocksDB state backend
- **State Storage:** S3 bucket for checkpoints and savepoints

### deploy.sh
Installs Flink Kubernetes Operator:
- Installs cert-manager (for webhooks)
- Installs Flink Operator via Helm (v1.13.0)
- Creates flink-operator namespace

## Performance Characteristics

### Throughput
- **Input:** 30,000 messages/second from Pulsar
- **Output:** ~500-1,000 aggregated records/minute to ClickHouse
- **Reduction ratio:** 1800x-3600x (due to 1-minute aggregation)

### Resource Usage
- **Total cluster:** 6GB RAM, 3 CPUs
- **JobManager:** 2GB RAM, 1 CPU
- **TaskManager:** 4GB RAM total (2x2GB), 2 CPUs, 4 task slots

### Scaling
- Increase TaskManager replicas for more parallelism
- Each TaskManager has 2 task slots = 2 parallel tasks
- Scales horizontally with more TaskManager pods

## Fault Tolerance

### Checkpointing
- **Interval:** 1 minute
- **Mode:** Exactly-once processing semantics
- **Storage:** S3 bucket (persistent across pod restarts)
- **Recovery:** Automatic restart from last successful checkpoint

### State Management
- **Backend:** RocksDB (for large state)
- **Persistence:** All state stored in S3
- **Batch Handling:** Flushes incomplete batches during checkpoints to prevent data loss

## Monitoring

### Logs
```bash
# JobManager logs
kubectl logs -n flink-benchmark <jobmanager-pod>

# TaskManager logs
kubectl logs -n flink-benchmark <taskmanager-pod>
```

### Flink Web UI
```bash
# Port forward to access UI
kubectl port-forward -n flink-benchmark <jobmanager-pod> 8081:8081
# Access at: http://localhost:8081
```

### Key Metrics
- **Records consumed:** Pulsar source metrics
- **Aggregation windows:** Log output shows device aggregation counts
- **Batch writes:** Console logs show batch execution (every 5K records or checkpoint)
- **Alerts:** Console logs show temperature, humidity, battery alerts

## Schema Mapping

### AVRO → SensorRecord Mapping
| AVRO Field | Type | SensorRecord Field | Notes |
|------------|------|-------------------|-------|
| sensorId | int | device_id | Converted to "sensor_{id}" |
| sensorType | int | device_type | Mapped to type names (1="temperature_sensor") |
| temperature | double | temperature | Direct mapping |
| humidity | double | humidity | Direct mapping |
| pressure | double | pressure | Direct mapping |
| batteryLevel | double | battery_level | Direct mapping |
| status | int | status | Direct mapping |
| - | - | customer_id | Default: "customer_0001" |
| - | - | site_id | Derived from sensorId |
| - | - | latitude/longitude | Default: 0.0 |
| - | - | co2_level, noise_level, etc. | Default values |

## Configuration

### Environment Variables (in YAML)
- `PULSAR_URL`: `pulsar://pulsar-proxy.pulsar.svc.cluster.local:6650`
- `PULSAR_ADMIN_URL`: `http://pulsar-proxy.pulsar.svc.cluster.local:8080`
- `PULSAR_TOPIC`: `persistent://public/default/iot-sensor-data`
- `CLICKHOUSE_URL`: `jdbc:clickhouse://clickhouse-iot-cluster-repl.clickhouse.svc.cluster.local:8123/benchmark`

### Tuning Parameters
- **BATCH_SIZE:** 5000 records (in ClickHouseJDBCSink)
- **Window Size:** 1 minute (in main method)
- **Parallelism:** Controlled by TaskManager replicas × task slots

## Common Operations

### Update Job Code
1. Modify Java files in `flink-consumer/src/`
2. Run `./build-and-push.sh`
3. Suspend job: `kubectl patch flinkdeployment iot-flink-job -n flink-benchmark --type merge -p '{"spec":{"job":{"state":"suspended"}}}'`
4. Resume job: `kubectl patch flinkdeployment iot-flink-job -n flink-benchmark --type merge -p '{"spec":{"job":{"state":"running"}}}'`

### Scale TaskManagers
```bash
kubectl patch flinkdeployment iot-flink-job -n flink-benchmark \
  --type merge -p '{"spec":{"taskManager":{"replicas":4}}}'
```

### Trigger Savepoint
```bash
kubectl patch flinkdeployment iot-flink-job -n flink-benchmark \
  --type merge -p '{"spec":{"job":{"savepointTriggerNonce":1}}}'
```

## Dependencies
- **Flink Version:** 1.17+
- **Pulsar Connector:** Official Flink Pulsar connector
- **ClickHouse JDBC:** ClickHouse JDBC driver
- **AVRO:** Apache AVRO for schema and serialization
- **State Backend:** RocksDB for state management

## Summary
The flink-load folder implements a robust, fault-tolerant streaming pipeline that:
1. **Consumes** high-volume AVRO-encoded sensor data from Pulsar
2. **Aggregates** data per device in 1-minute windows to reduce volume
3. **Writes** aggregated results to ClickHouse with exactly-once guarantees
4. **Scales** horizontally with Kubernetes and Flink Operator
5. **Recovers** automatically from failures using checkpoints

