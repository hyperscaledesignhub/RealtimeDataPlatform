# Local Docker Setup Commands for IoT Data Pipeline

## 1. Start Pulsar
```bash
docker run -d \
  -p 6650:6650 \
  -p 8080:8080 \
  --name pulsar-standalone \
  apachepulsar/pulsar:latest \
  bin/pulsar standalone
```
- Access: `pulsar://localhost:6650`
- Admin UI: `http://localhost:8080`

## 2. Start ClickHouse
```bash
docker run -d \
  --name clickhouse \
  -p 8123:8123 \
  -p 9000:9000 \
  --ulimit nofile=262144:262144 \
  -e CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT=1 \
  -e CLICKHOUSE_PASSWORD= \
  clickhouse/clickhouse-server
```
- HTTP: `http://localhost:8123`
- Native: `localhost:9000`

### Initialize ClickHouse Tables
```bash
docker exec -i clickhouse clickhouse-client < scripts/clickhouse-init.sql
```

### Connect to ClickHouse CLI
```bash
docker exec -it clickhouse clickhouse-client --database iot
```

## 3. Start Flink Cluster
```bash
# Create network
docker network create flink-network

# Start JobManager (Flink 1.18.0 - matches pom.xml version)
docker run -d \
  --name flink-jobmanager \
  --network flink-network \
  -p 8081:8081 \
  -e FLINK_PROPERTIES="jobmanager.rpc.address: flink-jobmanager" \
  flink:1.18.0 jobmanager

# Start TaskManager
docker run -d \
  --name flink-taskmanager \
  --network flink-network \
  -e FLINK_PROPERTIES="jobmanager.rpc.address: flink-jobmanager" \
  flink:1.18.0 taskmanager
```
- Flink UI: `http://localhost:8081`

## 4. Build and Deploy Flink Job

### Build the JAR
```bash
cd flink-consumer
mvn clean package -DskipTests
```

### Submit Flink Job
```bash
# Copy JAR to Flink container
docker cp target/flink-consumer-1.0.0.jar flink-jobmanager:/tmp/

# Submit job with environment variables
docker exec -e PULSAR_URL=pulsar://host.docker.internal:6650 \
  -e CLICKHOUSE_URL=jdbc:clickhouse://host.docker.internal:8123/iot \
  -e PULSAR_TOPIC=persistent://public/default/iot-sensor-data \
  flink-jobmanager flink run \
  --class com.iot.pipeline.flink.JDBCFlinkConsumer \
  /tmp/flink-consumer-1.0.0.jar
```

## 5. Start Producer (Optional - for testing)
```bash
cd producer
mvn clean package
java -jar target/producer-1.0.0.jar
```

Or run producer in Docker:
```bash
cd producer
docker build -t iot-producer .
docker run -d \
  --name iot-producer \
  -e PULSAR_URL=pulsar://host.docker.internal:6650 \
  iot-producer
```

## Quick Commands

### Stop All Containers
```bash
docker stop pulsar-standalone clickhouse flink-jobmanager flink-taskmanager iot-producer
docker rm pulsar-standalone clickhouse flink-jobmanager flink-taskmanager iot-producer
```

### Check Logs
```bash
docker logs pulsar-standalone
docker logs clickhouse
docker logs flink-jobmanager
docker logs flink-taskmanager
```

### Check Data in ClickHouse
```bash
# Quick query
docker exec clickhouse clickhouse-client --database iot --query "SELECT COUNT(*) FROM sensor_raw_data"

# Interactive session
docker exec -it clickhouse clickhouse-client --database iot
```

Then run:
```sql
SELECT * FROM sensor_raw_data ORDER BY timestamp DESC LIMIT 10;
SELECT alert_type, COUNT(*) FROM sensor_alerts GROUP BY alert_type;
```

### Monitor Flink Job
- Open: `http://localhost:8081`
- Check running jobs, task managers, and metrics

## Troubleshooting

### If containers already exist
```bash
docker rm -f pulsar-standalone clickhouse flink-jobmanager flink-taskmanager
```

### If ports are in use
```bash
# Find process using port (e.g., 8081)
lsof -i :8081
# Kill the process or use different ports
```

### Linux users (host.docker.internal doesn't work)
Replace `host.docker.internal` with your host IP:
```bash
HOST_IP=$(hostname -I | awk '{print $1}')
# Then use $HOST_IP instead of host.docker.internal
```

## Architecture
```
Producer → Pulsar (6650) → Flink Consumer → ClickHouse (8123)
                                ↓
                          Flink UI (8081)
```