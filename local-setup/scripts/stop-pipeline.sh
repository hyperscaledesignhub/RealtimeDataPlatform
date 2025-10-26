#!/bin/bash

echo "🛑 STOPPING IOT DATA PIPELINE..."
echo "================================"

echo "📊 Current Pipeline Status:"
docker ps --filter network=iot-network --format "  • {{.Names}}: {{.Status}}" 2>/dev/null

echo ""
echo "🔄 Stopping Flink Jobs..."
# Stop Flink jobs gracefully
docker exec flink-jobmanager /opt/flink/bin/flink list 2>/dev/null | grep RUNNING | awk '{print $4}' | while read jobid; do
    echo "  → Stopping Flink job: $jobid"
    docker exec flink-jobmanager /opt/flink/bin/flink stop $jobid 2>/dev/null || true
done

echo ""
echo "🐳 Stopping Docker Containers..."

# Stop containers in reverse dependency order
echo "  → Stopping IoT Producer..."
docker stop iot-producer 2>/dev/null && docker rm iot-producer 2>/dev/null || true

echo "  → Stopping Flink TaskManager..."
docker stop flink-taskmanager-1 2>/dev/null && docker rm flink-taskmanager-1 2>/dev/null || true

echo "  → Stopping Flink JobManager..."
docker stop flink-jobmanager 2>/dev/null && docker rm flink-jobmanager 2>/dev/null || true

echo "  → Stopping Pulsar..."
docker stop pulsar-standalone 2>/dev/null && docker rm pulsar-standalone 2>/dev/null || true

echo "  → Stopping ClickHouse..."
docker stop clickhouse 2>/dev/null && docker rm clickhouse 2>/dev/null || true

echo ""
echo "🧹 Cleaning Up Resources..."
echo "  → Removing Docker network..."
docker network rm iot-network 2>/dev/null || true

# Clean up any orphaned containers from the iot-network
echo "  → Cleaning up any remaining containers..."
docker ps -a --filter network=iot-network --format "{{.Names}}" 2>/dev/null | while read container; do
    docker stop $container 2>/dev/null && docker rm $container 2>/dev/null || true
done

echo ""
echo "✅ PIPELINE STOPPED SUCCESSFULLY!"
echo "================================="
echo ""
echo "🔧 Optional Cleanup Commands:"
echo "  • Remove Docker images: docker rmi \$(docker images -q --filter reference='*pulsar*' --filter reference='*flink*' --filter reference='*clickhouse*')"
echo "  • Clean Docker system: docker system prune -f"
echo ""
echo "🚀 To restart the pipeline:"
echo "  • bash scripts/start-pipeline.sh"
echo ""