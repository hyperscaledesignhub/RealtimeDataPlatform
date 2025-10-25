#!/bin/bash

echo "Stopping IoT Data Pipeline containers..."

# Stop and remove containers
docker stop iot-producer 2>/dev/null
docker rm iot-producer 2>/dev/null

docker stop flink-taskmanager-2 2>/dev/null
docker rm flink-taskmanager-2 2>/dev/null

docker stop flink-taskmanager-1 2>/dev/null
docker rm flink-taskmanager-1 2>/dev/null

docker stop flink-jobmanager 2>/dev/null
docker rm flink-jobmanager 2>/dev/null

docker stop grafana 2>/dev/null
docker rm grafana 2>/dev/null

docker stop clickhouse 2>/dev/null
docker rm clickhouse 2>/dev/null

docker stop pulsar-standalone 2>/dev/null
docker rm pulsar-standalone 2>/dev/null

# Remove network
docker network rm iot-network 2>/dev/null

echo "All containers stopped and removed."

# Optional: Remove volumes (uncomment if needed)
# echo "Removing volumes..."
# docker volume rm pulsar-data flink-data clickhouse-data grafana-data 2>/dev/null

echo "Pipeline stopped successfully!"