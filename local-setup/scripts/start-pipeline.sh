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
  -e CLICKHOUSE_DB=benchmark \
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
  -p 9249:9249 \
  -v "$PWD/config/flink-conf.yaml:/opt/flink/conf/flink-conf.yaml" \
  -e FLINK_PROPERTIES="jobmanager.rpc.address: flink-jobmanager" \
  flink:1.18.0 jobmanager > /dev/null

# Start Flink TaskManager
echo "  → Starting Flink TaskManager..."
docker run -d --name flink-taskmanager-1 \
  --network iot-network \
  -p 9250:9249 \
  -v "$PWD/config/flink-conf.yaml:/opt/flink/conf/flink-conf.yaml" \
  -e FLINK_PROPERTIES="jobmanager.rpc.address: flink-jobmanager
taskmanager.numberOfTaskSlots: 2" \
  flink:1.18.0 taskmanager > /dev/null

# Download and install Prometheus metrics reporter in containers
echo "  → Installing Prometheus metrics reporter..."
FLINK_PROMETHEUS_JAR="flink-metrics-prometheus-1.18.0.jar"
if [ ! -f "/tmp/$FLINK_PROMETHEUS_JAR" ]; then
    curl -s -L "https://repo1.maven.org/maven2/org/apache/flink/flink-metrics-prometheus/1.18.0/$FLINK_PROMETHEUS_JAR" \
        -o "/tmp/$FLINK_PROMETHEUS_JAR"
fi

# Copy JAR into Flink containers
docker cp "/tmp/$FLINK_PROMETHEUS_JAR" flink-jobmanager:/opt/flink/lib/
docker cp "/tmp/$FLINK_PROMETHEUS_JAR" flink-taskmanager-1:/opt/flink/lib/

# Restart Flink containers to load the metrics reporter
echo "  → Restarting Flink to load metrics reporter..."
docker restart flink-jobmanager > /dev/null
docker restart flink-taskmanager-1 > /dev/null

echo "⏳ Waiting for services to initialize..."
sleep 30

# Start Prometheus
echo "  → Starting Prometheus..."
docker run -d --name prometheus \
  --network iot-network \
  -p 9090:9090 \
  -v "$PWD/config/prometheus.yml:/etc/prometheus/prometheus.yml" \
  prom/prometheus:latest > /dev/null

# Start Grafana
echo "  → Starting Grafana..."
docker run -d --name grafana \
  --network iot-network \
  -p 3000:3000 \
  -e GF_SECURITY_ADMIN_PASSWORD=admin \
  -e GF_INSTALL_PLUGINS=grafana-clickhouse-datasource \
  -v "$PWD/config/grafana-datasource.yaml:/etc/grafana/provisioning/datasources/datasource.yaml" \
  -v "$PWD/config/grafana-dashboard-provisioning.yaml:/etc/grafana/provisioning/dashboards/dashboard.yaml" \
  -v "$PWD/config/flink-dashboard.json:/etc/grafana/provisioning/dashboards/flink-dashboard.json" \
  -v "$PWD/config/clickhouse-dashboard.json:/etc/grafana/provisioning/dashboards/clickhouse-dashboard.json" \
  -v "$PWD/config/pulsar-dashboard.json:/etc/grafana/provisioning/dashboards/pulsar-dashboard.json" \
  grafana/grafana:10.0.0 > /dev/null

echo "⏳ Waiting for monitoring stack to initialize..."
sleep 15

echo "🔧 Initializing Database Schema..."
docker exec clickhouse clickhouse-client --multiquery < scripts/clickhouse-init.sql 2>/dev/null || true

echo "📡 Starting IoT Performance Producer with AVRO..."
docker run -d --name iot-producer \
  --network iot-network \
  -v "$PWD/scripts:/scripts" \
  -w /scripts \
  eclipse-temurin:17-jre \
  /scripts/pulsar-sensor-perf \
  -r 100 \
  -u pulsar://pulsar-standalone:6650 \
  --device-id-min 1 \
  --device-id-max 100 \
  --device-prefix device_ \
  --num-customers 10 \
  --num-sites 5 \
  --use-avro \
  persistent://public/default/iot-sensor-data > /dev/null

echo "⏳ Waiting for producer to start..."
sleep 10

echo "🔄 Deploying Flink Consumer Job..."
# Get container IPs
PULSAR_IP=$(docker inspect pulsar-standalone --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
CLICKHOUSE_IP=$(docker inspect clickhouse --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')

# Copy JAR and submit Flink job
docker cp flink-consumer/target/flink-consumer-1.0.0.jar flink-jobmanager:/opt/flink/
docker exec -e PULSAR_URL="pulsar://$PULSAR_IP:6650" -e CLICKHOUSE_URL="jdbc:clickhouse://$CLICKHOUSE_IP:8123/benchmark" flink-jobmanager /opt/flink/bin/flink run --class com.iot.pipeline.flink.JDBCFlinkConsumer /opt/flink/flink-consumer-1.0.0.jar > /dev/null 2>&1 &

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
echo "  • Grafana: http://localhost:3000 (admin/admin)"
echo "  • Prometheus: http://localhost:9090"
echo ""
echo "📈 Grafana Dashboards:"
echo "  • Flink Metrics: http://localhost:3000/d/flink-iot-pipeline"
echo "  • ClickHouse Data: http://localhost:3000/d/clickhouse-iot-metrics"
echo "  • Pulsar Metrics: http://localhost:3000/d/pulsar-metrics"
echo ""
echo "🔍 Raw Metrics:"
echo "  • JobManager: http://localhost:9249/metrics"
echo "  • TaskManager: http://localhost:9250/metrics"
echo "  • Pulsar: http://localhost:8080/metrics"
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