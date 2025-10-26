#!/bin/bash

echo "🚀 STARTING IOT DATA PIPELINE..."
echo "================================"

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "📦 Building Components..."

# Build the producer
echo "  → Building IoT Producer..."
cd producer
mvn clean package -q
if [ $? -ne 0 ]; then
    echo "❌ Producer build failed!"
    exit 1
fi
cd ..

# Build the Flink consumer
echo "  → Building Flink Consumer..."
cd flink-consumer
mvn clean package -q
if [ $? -ne 0 ]; then
    echo "❌ Flink Consumer build failed!"
    exit 1
fi
cd ..

echo "🐳 Starting Docker Infrastructure..."

# Create network
docker network create iot-network 2>/dev/null || true

# Start ClickHouse
echo "  → Starting ClickHouse..."
docker run -d --name clickhouse \
  --network iot-network \
  -p 8123:8123 -p 9000:9000 \
  -v "$PWD/scripts/clickhouse-init.sql:/docker-entrypoint-initdb.d/init.sql" \
  -v "$PWD/scripts/clickhouse-users.xml:/etc/clickhouse-server/users.d/users.xml" \
  -e CLICKHOUSE_DB=iot \
  -e CLICKHOUSE_USER=default \
  -e CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT=1 \
  clickhouse/clickhouse-server:latest > /dev/null

# Start Pulsar
echo "  → Starting Pulsar..."
docker run -d --name pulsar-standalone \
  --network iot-network \
  -p 6650:6650 -p 8080:8080 \
  apachepulsar/pulsar:3.1.0 bin/pulsar standalone > /dev/null

# Start Flink JobManager
echo "  → Starting Flink JobManager..."
docker run -d --name flink-jobmanager \
  --network iot-network \
  -p 8081:8081 \
  -e FLINK_PROPERTIES="jobmanager.rpc.address: flink-jobmanager" \
  flink:1.18.0 jobmanager > /dev/null

# Start Flink TaskManager
echo "  → Starting Flink TaskManager..."
docker run -d --name flink-taskmanager-1 \
  --network iot-network \
  -e FLINK_PROPERTIES="jobmanager.rpc.address: flink-jobmanager
taskmanager.numberOfTaskSlots: 2" \
  flink:1.18.0 taskmanager > /dev/null

echo "⏳ Waiting for services to initialize..."
sleep 45

echo "🔧 Initializing Database Schema..."
docker exec clickhouse clickhouse-client --multiquery < scripts/clickhouse-init.sql 2>/dev/null || true

echo "📡 Starting IoT Producer..."
docker run -d --name iot-producer \
  --network iot-network \
  -e PULSAR_URL="pulsar://pulsar-standalone:6650" \
  -v "$PWD/producer/target/producer-1.0.0.jar:/app/producer.jar" \
  openjdk:11-jre-slim \
  java -jar /app/producer.jar > /dev/null

echo "⏳ Waiting for producer to start..."
sleep 10

echo "🔄 Deploying Flink Consumer Job..."
# Get container IPs
PULSAR_IP=$(docker inspect pulsar-standalone --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
CLICKHOUSE_IP=$(docker inspect clickhouse --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')

# Copy JAR and submit Flink job
docker cp flink-consumer/target/flink-consumer-1.0.0.jar flink-jobmanager:/opt/flink/
docker exec -e PULSAR_URL="pulsar://$PULSAR_IP:6650" -e CLICKHOUSE_URL="jdbc:clickhouse://$CLICKHOUSE_IP:8123/iot" flink-jobmanager /opt/flink/bin/flink run --class com.iot.pipeline.flink.JDBCFlinkConsumer /opt/flink/flink-consumer-1.0.0.jar > /dev/null 2>&1 &

echo "⏳ Waiting for Flink job to initialize..."
sleep 15

echo ""
echo "🎉 PIPELINE STARTED SUCCESSFULLY!"
echo "================================="
echo ""
echo "📊 Access Points:"
echo "  • Pulsar Admin UI: http://localhost:8080"
echo "  • Flink Dashboard: http://localhost:8081"
echo "  • ClickHouse HTTP: http://localhost:8123"
echo ""
echo "🔍 Monitoring Commands:"
echo "  • Check status: docker ps --filter network=iot-network"
echo "  • Monitor data: bash scripts/monitor-data-flow.sh" 
echo "  • View logs: bash scripts/docker-logs.sh"
echo "  • Test pipeline: bash scripts/test-consumer.sh"
echo ""
echo "🛑 To stop the pipeline:"
echo "  • bash scripts/stop-pipeline.sh"
echo ""