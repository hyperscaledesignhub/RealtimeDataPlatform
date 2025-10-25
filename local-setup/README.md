# Local Development Setup - Event Streaming Pipeline

Complete local development environment for testing the event streaming pipeline using **Docker** or **Kubernetes (Kind)**. This setup runs Apache Pulsar, Apache Flink, and ClickHouse on your local machine for development and testing.

## Overview

This folder provides a **lightweight, local version** of the production platform for:
- **Development:** Code and test locally before deploying to AWS
- **Learning:** Understand how components interact
- **Testing:** Validate changes without cloud costs
- **Demos:** Show the platform in action

**Architecture:** Producer → Pulsar → Flink → ClickHouse

---

## 🚀 Quick Start

### Prerequisites

✅ **Docker & Docker Compose** installed  
✅ **Java 11+** installed  
✅ **Maven 3.6+** installed  
✅ **kubectl** (for Kubernetes setup)

### Option 1: Docker Compose Setup (Recommended for Beginners)

**Start the entire pipeline with one command:**

```bash
cd /Users/vijayabhaskarv/IOT/github/RealtimeDataPlatform/local-setup

# Start all services (Pulsar, Flink, ClickHouse, Producer)
./scripts/start-pipeline.sh
```

**What this does:**
1. Builds Java applications (Producer, Flink Consumer)
2. Starts Docker containers:
   - Pulsar (broker + standalone)
   - Flink (JobManager + TaskManager)
   - ClickHouse database
   - Producer (event generator)
3. Creates ClickHouse schema
4. Deploys Flink job
5. Shows logs and status

**Wait ~2-3 minutes** for all services to be ready.

**Stop the pipeline:**

```bash
./scripts/stop-pipeline.sh
```

**What this does:**
1. Stops Flink job gracefully
2. Stops all Docker containers
3. Preserves data in Docker volumes (optional: use `docker-compose down -v` to delete data)

### Option 2: Kubernetes (Kind) Setup

For a more production-like local environment:

```bash
cd k8s

# Create Kind cluster
./create-cluster.sh

# Deploy all components
./deploy-kind.sh

# Start the pipeline
./start-pipeline.sh

# Access services
./port-forward.sh

# Stop the pipeline
./stop-pipeline.sh
```

---

## 📊 Access Services

After starting the pipeline, access the web UIs:

| Service | URL | Credentials |
|---------|-----|-------------|
| **Pulsar Admin** | http://localhost:8080 | - |
| **Flink Web UI** | http://localhost:8081 | - |
| **ClickHouse** | http://localhost:8123 | default / (no password) |
| **Grafana** | http://localhost:3000 | admin / admin |

---

## 📁 Directory Structure

```
local-setup/
├── README.md                      (This file)
├── docker-local-setup.md          (Docker Compose detailed guide)
├── PIPELINE_MANAGEMENT.md         (Operations guide)
│
├── docker/
│   └── docker-compose.yml         (All services defined)
│
├── producer/                      (Event data generator)
│   ├── src/main/java/...
│   ├── pom.xml
│   └── Dockerfile
│
├── flink-consumer/                (Flink streaming job)
│   ├── src/main/java/...
│   └── pom.xml
│
├── k8s/                           (Kubernetes manifests for Kind)
│   ├── pulsar.yaml
│   ├── flink.yaml
│   ├── clickhouse.yaml
│   ├── producer.yaml
│   ├── create-cluster.sh
│   ├── deploy-kind.sh
│   ├── start-pipeline.sh
│   └── stop-pipeline.sh
│
├── config/
│   └── grafana-dashboard.json     (Pre-built dashboards)
│
└── scripts/                       (Utility scripts)
    ├── start-pipeline.sh          ⭐ START THE PIPELINE
    ├── stop-pipeline.sh           ⭐ STOP THE PIPELINE
    ├── status-pipeline.sh         (Check status)
    ├── monitor-data-flow.sh       (Monitor data flow)
    ├── docker-logs.sh             (View logs)
    ├── clickhouse-query.sh        (Run queries)
    ├── simple-pulsar-consumer.py  (Test consumer)
    └── test-consumer.sh           (Test consumer)
```

---

## 🎯 Running the Pipeline

### Start Pipeline

```bash
# Navigate to local-setup directory
cd local-setup

# Make scripts executable (first time only)
chmod +x scripts/*.sh

# Start the entire pipeline
./scripts/start-pipeline.sh
```

**Expected output:**
```
🚀 Starting IoT Data Pipeline...
✅ Building producer...
✅ Building Flink consumer...
✅ Starting Docker containers...
✅ Creating ClickHouse schema...
✅ Starting producer...
✅ Deploying Flink job...
✅ Pipeline started successfully!

Access services:
- Pulsar: http://localhost:8080
- Flink: http://localhost:8081
- ClickHouse: http://localhost:8123
- Grafana: http://localhost:3000
```

### Stop Pipeline

```bash
./scripts/stop-pipeline.sh
```

**Expected output:**
```
🛑 Stopping IoT Data Pipeline...
✅ Stopping Flink job...
✅ Stopping producer...
✅ Stopping Docker containers...
✅ Pipeline stopped successfully!

Data is preserved in Docker volumes.
To delete all data: docker-compose down -v
```

### Check Pipeline Status

```bash
./scripts/status-pipeline.sh
```

**Shows:**
- Running containers
- Flink job status
- Pulsar topic stats
- ClickHouse connection status

### Monitor Data Flow

```bash
./scripts/monitor-data-flow.sh
```

**Shows real-time:**
- Producer message rate
- Pulsar topic throughput
- Flink processing rate
- ClickHouse insert rate

---

## 💾 Data Flow Verification

### 1. Check Producer is Sending Data

```bash
# View producer logs
docker logs -f iot-producer

# Or use the script
./scripts/docker-logs.sh producer
```

**Expected:** "Sent 100 messages" (or similar)

### 2. Check Pulsar Topic

```bash
# Using Pulsar admin
docker exec pulsar bin/pulsar-admin topics stats persistent://public/default/iot-sensor-data

# Or use Python consumer
python3 scripts/simple-pulsar-consumer.py
```

### 3. Check Flink is Processing

```bash
# View Flink Web UI
open http://localhost:8081

# Check TaskManager logs
docker logs -f flink-taskmanager
```

### 4. Query ClickHouse Data

```bash
# Using the query script
./scripts/clickhouse-query.sh "SELECT count() FROM iot.sensor_metrics"

# Or connect directly
docker exec -it clickhouse clickhouse-client

# Run queries
SELECT * FROM iot.sensor_metrics ORDER BY window_start DESC LIMIT 10;
SELECT count(*) FROM iot.sensor_alerts WHERE alert_type != 'NORMAL';
```

---

## 🔧 Common Operations

### View Logs

```bash
# All services
docker-compose logs -f

# Specific service
docker logs -f iot-producer
docker logs -f flink-jobmanager
docker logs -f flink-taskmanager
docker logs -f clickhouse

# Using script
./scripts/docker-logs.sh producer
./scripts/docker-logs.sh flink
./scripts/docker-logs.sh clickhouse
```

### Restart a Component

```bash
# Restart producer
docker-compose restart producer

# Restart Flink
docker-compose restart flink-jobmanager flink-taskmanager

# Restart all
docker-compose restart
```

### Clean Up and Reset

```bash
# Stop pipeline
./scripts/stop-pipeline.sh

# Remove all containers and volumes (deletes data!)
docker-compose down -v

# Clean up Docker
docker system prune -f
```

---

## 📝 Example Queries

### View Recent Sensor Data

```sql
-- Connect to ClickHouse
docker exec -it clickhouse clickhouse-client

-- Recent aggregated metrics (1-minute windows)
SELECT 
  window_start,
  sensor_id,
  avg_temperature,
  avg_humidity,
  max_temperature,
  min_battery_level
FROM iot.sensor_metrics
ORDER BY window_start DESC
LIMIT 20;
```

### Check for Alerts

```sql
-- View alerts in last hour
SELECT 
  alert_time,
  sensor_id,
  alert_type,
  temperature,
  humidity,
  battery_level
FROM iot.sensor_alerts
WHERE alert_time >= now() - INTERVAL 1 HOUR
  AND alert_type != 'NORMAL'
ORDER BY alert_time DESC;
```

### Sensor Statistics

```sql
-- Count by sensor type
SELECT 
  sensor_type,
  count(*) as total_readings,
  avg(avg_temperature) as avg_temp,
  max(max_temperature) as max_temp
FROM iot.sensor_metrics
WHERE window_start >= now() - INTERVAL 1 HOUR
GROUP BY sensor_type
ORDER BY total_readings DESC;
```

---

## 🐛 Troubleshooting

### Pipeline Won't Start

**Check Docker is running:**
```bash
docker ps
```

**Check ports are available:**
```bash
# Required ports: 6650, 8080, 8081, 8123, 3000, 9092
lsof -i :6650  # Pulsar
lsof -i :8081  # Flink
lsof -i :8123  # ClickHouse
```

**View detailed logs:**
```bash
docker-compose logs
```

### No Data in ClickHouse

**Check producer is running:**
```bash
docker ps | grep producer
docker logs iot-producer
```

**Check Pulsar has messages:**
```bash
docker exec pulsar bin/pulsar-admin topics stats persistent://public/default/iot-sensor-data
```

**Check Flink is consuming:**
```bash
docker logs flink-taskmanager | grep "Processing"
```

### Flink Job Failed

**Check JobManager logs:**
```bash
docker logs flink-jobmanager
```

**Common issues:**
- Pulsar not reachable → Check `docker ps | grep pulsar`
- ClickHouse not reachable → Check `docker ps | grep clickhouse`
- Out of memory → Increase Docker memory limit (Docker Desktop → Settings → Resources)

### Services Not Accessible

**Verify containers are running:**
```bash
docker ps
```

**Restart Docker:**
```bash
docker-compose down
docker-compose up -d
```

---

## 📊 Performance Expectations

### Local Setup Performance

**Producer:**
- Rate: 100-1,000 messages/second (configurable)
- Limited by local machine resources

**Pulsar:**
- Throughput: Up to 10K msg/sec locally
- Storage: Docker volume (persistent)

**Flink:**
- Processing: 100-1K records/second
- Memory: 1-2 GB (configurable in docker-compose.yml)

**ClickHouse:**
- Inserts: ~10-100 records/second (aggregated)
- Queries: <50ms for recent data
- Storage: Docker volume (persistent)

### Resource Usage

**Minimum Requirements:**
- CPU: 4 cores
- RAM: 8 GB
- Disk: 20 GB free space

**Recommended:**
- CPU: 8 cores
- RAM: 16 GB
- Disk: 50 GB free space
- SSD for better performance

---

## 🔄 Development Workflow

### 1. Make Code Changes

Edit files in `producer/` or `flink-consumer/`:
```bash
# Example: Modify producer rate
vim producer/src/main/java/com/iot/pipeline/producer/IoTDataProducer.java
```

### 2. Rebuild

```bash
# Rebuild specific component
cd producer && mvn clean package
cd flink-consumer && mvn clean package
```

### 3. Restart Component

```bash
# Restart producer
docker-compose restart producer

# Restart Flink (to pick up new job)
docker-compose restart flink-jobmanager flink-taskmanager
```

### 4. Verify Changes

```bash
# Check logs
docker logs -f iot-producer

# Check metrics
./scripts/status-pipeline.sh
```

---

## 📦 Docker Compose Services

### Services Defined in docker/docker-compose.yml

1. **pulsar** - Message broker (Apache Pulsar standalone)
2. **flink-jobmanager** - Flink job coordination
3. **flink-taskmanager** - Flink parallel processing
4. **clickhouse** - Analytics database
5. **producer** - Event data generator
6. **grafana** - Dashboards and visualization

### Networking

All services communicate on Docker network `pipeline-network`:
- pulsar:6650 (Pulsar service URL)
- flink-jobmanager:8081 (Flink Web UI)
- clickhouse:8123 (ClickHouse HTTP)
- clickhouse:9000 (ClickHouse Native)

---

## 🎓 Learning Resources

### Understand the Pipeline

1. **Start simple:** Run `./scripts/start-pipeline.sh` and observe logs
2. **View data flow:** Use `./scripts/monitor-data-flow.sh`
3. **Query data:** Connect to ClickHouse and run sample queries
4. **Check metrics:** Open Flink UI at http://localhost:8081
5. **Visualize:** Open Grafana at http://localhost:3000

### Code Walkthrough

**Producer (`producer/src/main/java/`):**
- `IoTDataProducer.java` - Generates and sends events
- `SensorData.java` - Data model

**Flink Consumer (`flink-consumer/src/main/java/`):**
- `JDBCFlinkConsumer.java` - Main Flink job (JDBC sink)
- `SimpleFlinkConsumer.java` - Simple consumer example
- `FlinkIoTProcessor.java` - Flink SQL processing

**ClickHouse Schema (`scripts/clickhouse-init.sql`):**
- Table definitions
- Materialized views
- Alert rules

---

## 🆚 Local vs AWS Setups

| Feature | Local Setup | AWS 50K | AWS 1M |
|---------|-------------|---------|--------|
| **Throughput** | 100-1K msg/sec | 50K msg/sec | 250K+ msg/sec |
| **Infrastructure** | Docker/Kind | EKS + t3 | EKS + c5/r6id |
| **Storage** | Docker volumes | EBS gp3 | NVMe SSD |
| **Cost** | $0 (local) | ~$200/month | ~$3,500/month |
| **Use Case** | Dev/test/demo | Small-medium prod | Enterprise prod |
| **Setup Time** | 5 minutes | 50 minutes | 55 minutes |

---

## 🛠️ Utility Scripts Reference

### Pipeline Management

| Script | Purpose |
|--------|---------|
| `start-pipeline.sh` | ⭐ Start entire pipeline (build + deploy) |
| `stop-pipeline.sh` | ⭐ Stop entire pipeline gracefully |
| `status-pipeline.sh` | Check status of all components |
| `monitor-data-flow.sh` | Real-time monitoring of data flow |

### Docker Operations

| Script | Purpose |
|--------|---------|
| `docker-logs.sh` | View logs for specific service |
| `docker-standalone.sh` | Run components individually |
| `docker-stop.sh` | Stop Docker containers |

### Testing & Debugging

| Script | Purpose |
|--------|---------|
| `simple-pulsar-consumer.py` | Test Pulsar consumption |
| `test-consumer.sh` | Validate Pulsar messages |
| `clickhouse-query.sh` | Run ClickHouse queries from CLI |

### Kubernetes (Kind)

| Script | Purpose |
|--------|---------|
| `k8s/create-cluster.sh` | Create local Kind cluster |
| `k8s/deploy-kind.sh` | Deploy all components to Kind |
| `k8s/start-pipeline.sh` | Start pipeline in Kubernetes |
| `k8s/stop-pipeline.sh` | Stop pipeline in Kubernetes |
| `k8s/port-forward.sh` | Port-forward services for access |

---

## 🎯 Common Use Cases

### Test New Producer Logic

```bash
# 1. Modify producer code
vim producer/src/main/java/com/iot/pipeline/producer/IoTDataProducer.java

# 2. Rebuild
cd producer && mvn clean package && cd ..

# 3. Restart producer
docker-compose restart producer

# 4. Check logs
docker logs -f iot-producer
```

### Test Flink Transformations

```bash
# 1. Modify Flink consumer
vim flink-consumer/src/main/java/com/iot/pipeline/flink/JDBCFlinkConsumer.java

# 2. Rebuild
cd flink-consumer && mvn clean package && cd ..

# 3. Restart Flink
docker-compose restart flink-jobmanager flink-taskmanager

# 4. Check Flink UI
open http://localhost:8081
```

### Test ClickHouse Queries

```bash
# Connect to ClickHouse
docker exec -it clickhouse clickhouse-client

# Test your queries
SELECT count(*) FROM iot.sensor_metrics;

# Or use script
./scripts/clickhouse-query.sh "SELECT * FROM iot.sensor_metrics LIMIT 10"
```

---

## 🔍 Monitoring & Debugging

### Check Pipeline Health

```bash
# Check all services status
./scripts/status-pipeline.sh
```

**Expected output:**
```
✅ Pulsar: Running
✅ Flink JobManager: Running
✅ Flink TaskManager: Running
✅ ClickHouse: Running
✅ Producer: Running
✅ Data flowing: YES
```

### Monitor Real-Time Data Flow

```bash
./scripts/monitor-data-flow.sh
```

**Shows:**
- Messages/second from producer
- Pulsar topic throughput
- Flink processing rate
- ClickHouse insert rate

### View Component Logs

```bash
# All logs
docker-compose logs -f

# Specific component
./scripts/docker-logs.sh producer
./scripts/docker-logs.sh flink
./scripts/docker-logs.sh clickhouse
./scripts/docker-logs.sh pulsar
```

---

## 📈 Scaling for Local Testing

### Increase Message Rate

Edit `docker-compose.yml`:
```yaml
producer:
  environment:
    - MESSAGES_PER_SECOND=1000  # Increase from 100
```

Restart:
```bash
docker-compose restart producer
```

### Increase Flink Parallelism

Edit `docker-compose.yml`:
```yaml
flink-taskmanager:
  environment:
    - JOB_MANAGER_RPC_ADDRESS=flink-jobmanager
    - TASK_MANAGER_NUMBER_OF_TASK_SLOTS=4  # Increase from 2
```

### Add More Memory

Edit `docker-compose.yml`:
```yaml
flink-taskmanager:
  environment:
    - JVM_ARGS=-Xms2048m -Xmx4096m  # Increase heap
```

---

## 🧹 Cleanup

### Keep Data, Stop Services

```bash
./scripts/stop-pipeline.sh
```

### Delete Everything (Including Data)

```bash
# Stop and remove containers + volumes
docker-compose down -v

# Clean up Docker system
docker system prune -a -f
```

---

## 🚀 Next Steps

After running locally:

1. **Deploy to AWS 50K setup** - See `../aws-infra-50k-mps/DEPLOYMENT-RUNBOOK.md`
2. **Deploy to AWS 1M setup** - See `../aws-infra-1milion-mps/DEPLOYMENT-RUNBOOK.md`
3. **Customize for your domain:**
   - Modify data model in `SensorData.java`
   - Update schema in `scripts/clickhouse-init.sql`
   - Adjust Flink processing logic

---

## 📚 Additional Documentation

- **[Docker Setup Guide](./docker-local-setup.md)** - Detailed Docker Compose instructions
- **[Pipeline Management](./PIPELINE_MANAGEMENT.md)** - Operations and troubleshooting
- **[K8s Setup](./k8s/README.md)** - Kubernetes (Kind) local cluster guide

---

## Summary

The local-setup provides a **complete, self-contained environment** for:

✅ **Quick testing** - Start/stop with single command  
✅ **Development** - Edit code, rebuild, restart  
✅ **Learning** - Understand component interactions  
✅ **Demos** - Show platform capabilities  
✅ **No cost** - Runs entirely on local machine  
✅ **Easy transition** - Same code deploys to AWS  

**Start now:** `./scripts/start-pipeline.sh`  
**Stop anytime:** `./scripts/stop-pipeline.sh`