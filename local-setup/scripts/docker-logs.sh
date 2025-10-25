#!/bin/bash

SERVICE=$1

if [ -z "$SERVICE" ]; then
  echo "Usage: ./docker-logs.sh <service-name>"
  echo ""
  echo "Available services:"
  echo "  - pulsar-standalone"
  echo "  - clickhouse"
  echo "  - flink-jobmanager"
  echo "  - flink-taskmanager-1"
  echo "  - flink-taskmanager-2"
  echo "  - iot-producer"
  echo "  - grafana"
  echo ""
  echo "Example: ./docker-logs.sh flink-jobmanager"
  exit 1
fi

echo "Showing logs for $SERVICE..."
docker logs -f $SERVICE