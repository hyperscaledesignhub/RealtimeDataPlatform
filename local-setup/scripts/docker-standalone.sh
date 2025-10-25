#!/bin/bash

# Create network
echo "Creating Docker network..."
docker network create iot-network 2>/dev/null || true

# Start Pulsar
echo "Starting Apache Pulsar..."
docker run -d \
  --name pulsar-standalone \
  --network iot-network \
  -p 6650:6650 \
  -p 8080:8080 \
  -v pulsar-data:/pulsar/data \
  -e PULSAR_MEM="-Xms512m -Xmx512m -XX:MaxDirectMemorySize=512m" \
  apachepulsar/pulsar:3.1.0 \
  bin/pulsar standalone

# Start ClickHouse
echo "Starting ClickHouse..."
docker run -d \
  --name clickhouse \
  --network iot-network \
  -p 8123:8123 \
  -p 9000:9000 \
  -v clickhouse-data:/var/lib/clickhouse \
  -v $(pwd)/scripts/clickhouse-init.sql:/docker-entrypoint-initdb.d/init.sql \
  -e CLICKHOUSE_DB=iot \
  -e CLICKHOUSE_USER=default \
  -e CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT=1 \
  --ulimit nofile=262144:262144 \
  clickhouse/clickhouse-server:23.8

# Start Flink JobManager
echo "Starting Flink JobManager..."
docker run -d \
  --name flink-jobmanager \
  --network iot-network \
  -p 8081:8081 \
  -p 6123:6123 \
  -v flink-data:/opt/flink/data \
  -v $(pwd)/flink-consumer/target:/opt/flink/jars \
  -e JOB_MANAGER_RPC_ADDRESS=flink-jobmanager \
  -e FLINK_PROPERTIES="jobmanager.rpc.address:flink-jobmanager" \
  flink:1.18.0 \
  jobmanager

# Start Flink TaskManager 1
echo "Starting Flink TaskManager 1..."
docker run -d \
  --name flink-taskmanager-1 \
  --network iot-network \
  -v flink-data:/opt/flink/data \
  -v $(pwd)/flink-consumer/target:/opt/flink/jars \
  -e JOB_MANAGER_RPC_ADDRESS=flink-jobmanager \
  -e TASK_MANAGER_NUMBER_OF_TASK_SLOTS=2 \
  -e FLINK_PROPERTIES="jobmanager.rpc.address:flink-jobmanager" \
  flink:1.18.0 \
  taskmanager

# Start Flink TaskManager 2
echo "Starting Flink TaskManager 2..."
docker run -d \
  --name flink-taskmanager-2 \
  --network iot-network \
  -v flink-data:/opt/flink/data \
  -v $(pwd)/flink-consumer/target:/opt/flink/jars \
  -e JOB_MANAGER_RPC_ADDRESS=flink-jobmanager \
  -e TASK_MANAGER_NUMBER_OF_TASK_SLOTS=2 \
  -e FLINK_PROPERTIES="jobmanager.rpc.address:flink-jobmanager" \
  flink:1.18.0 \
  taskmanager

# Start Grafana (optional)
echo "Starting Grafana..."
docker run -d \
  --name grafana \
  --network iot-network \
  -p 3000:3000 \
  -v grafana-data:/var/lib/grafana \
  -v $(pwd)/config/grafana-dashboard.json:/etc/grafana/provisioning/dashboards/iot-dashboard.json \
  -e GF_SECURITY_ADMIN_PASSWORD=admin \
  -e GF_INSTALL_PLUGINS=grafana-clickhouse-datasource \
  grafana/grafana:10.0.0

echo "Waiting for services to start..."
sleep 30

# Build and start IoT Producer
echo "Building IoT Producer..."
cd producer
docker build -t iot-producer:latest .
cd ..

echo "Starting IoT Producer..."
docker run -d \
  --name iot-producer \
  --network iot-network \
  -e PULSAR_URL=pulsar://pulsar-standalone:6650 \
  -e PULSAR_TOPIC=persistent://public/default/iot-sensor-data \
  --restart unless-stopped \
  iot-producer:latest

# Submit Flink Job
echo "Submitting Flink Job..."
docker run --rm \
  --name flink-job-submit \
  --network iot-network \
  -v $(pwd)/flink-consumer/target:/opt/flink/jars \
  -e PULSAR_URL=pulsar://pulsar-standalone:6650 \
  -e PULSAR_TOPIC=persistent://public/default/iot-sensor-data \
  -e CLICKHOUSE_URL=jdbc:clickhouse://clickhouse:8123/iot \
  flink:1.18.0 \
  flink run -m flink-jobmanager:8081 /opt/flink/jars/flink-consumer-1.0.0.jar

echo "IoT Data Pipeline started successfully!"
echo ""
echo "Service URLs:"
echo "  - Pulsar Admin: http://localhost:8080"
echo "  - Flink UI: http://localhost:8081"
echo "  - ClickHouse: http://localhost:8123"
echo "  - Grafana: http://localhost:3000 (admin/admin)"
echo ""
echo "Container Status:"
docker ps --filter "network=iot-network" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"