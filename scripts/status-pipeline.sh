#!/bin/bash

echo "📊 IOT DATA PIPELINE STATUS"
echo "=========================="
echo

# Check if containers are running
echo "🐳 Container Status:"
if docker network ls | grep -q iot-network; then
    docker ps --filter network=iot-network --format "  • {{.Names}}: {{.Status}} ({{.Ports}})" 2>/dev/null
    if [ $? -ne 0 ] || [ -z "$(docker ps --filter network=iot-network -q)" ]; then
        echo "  • No containers running in iot-network"
    fi
else
    echo "  • Network 'iot-network' not found - Pipeline appears to be stopped"
fi

echo

# Check Flink jobs if JobManager is running
if docker ps --filter name=flink-jobmanager --format "{{.Names}}" | grep -q flink-jobmanager; then
    echo "🔄 Flink Jobs:"
    FLINK_JOBS=$(docker exec flink-jobmanager /opt/flink/bin/flink list 2>/dev/null | grep -E "(RUNNING|FINISHED|FAILED)" | sed 's/^/  • /')
    if [ -z "$FLINK_JOBS" ]; then
        echo "  • No Flink jobs found"
    else
        echo "$FLINK_JOBS"
    fi
    echo
fi

# Check data if ClickHouse is running
if docker ps --filter name=clickhouse --format "{{.Names}}" | grep -q clickhouse; then
    echo "📈 Data Metrics:"
    SENSOR_COUNT=$(docker exec clickhouse clickhouse-client --query="SELECT COUNT(*) FROM iot.sensor_raw_data" 2>/dev/null)
    ALERT_COUNT=$(docker exec clickhouse clickhouse-client --query="SELECT COUNT(*) FROM iot.sensor_alerts" 2>/dev/null)
    
    if [ -n "$SENSOR_COUNT" ] && [ -n "$ALERT_COUNT" ]; then
        echo "  • Sensor Records: $SENSOR_COUNT"
        echo "  • Alert Records: $ALERT_COUNT"
        
        # Show latest record timestamp
        LATEST_RECORD=$(docker exec clickhouse clickhouse-client --query="SELECT max(timestamp) FROM iot.sensor_raw_data" 2>/dev/null)
        if [ -n "$LATEST_RECORD" ] && [ "$LATEST_RECORD" != "1900-01-01 00:00:00" ]; then
            echo "  • Latest Record: $LATEST_RECORD"
        fi
    else
        echo "  • Unable to connect to ClickHouse database"
    fi
    echo
fi

# Check Pulsar if running
if docker ps --filter name=pulsar-standalone --format "{{.Names}}" | grep -q pulsar-standalone; then
    echo "📡 Pulsar Metrics:"
    PULSAR_STATS=$(curl -s "http://localhost:8080/admin/v2/persistent/public/default/iot-sensor-data/stats" 2>/dev/null)
    if [ -n "$PULSAR_STATS" ]; then
        MSG_IN=$(echo "$PULSAR_STATS" | jq -r '.msgInCounter // "N/A"' 2>/dev/null)
        MSG_OUT=$(echo "$PULSAR_STATS" | jq -r '.msgOutCounter // "N/A"' 2>/dev/null)
        echo "  • Messages In: $MSG_IN"
        echo "  • Messages Out: $MSG_OUT"
    else
        echo "  • Unable to fetch Pulsar statistics"
    fi
    echo
fi

echo "🔧 Management Commands:"
echo "  • Start Pipeline: bash scripts/start-pipeline.sh"
echo "  • Stop Pipeline: bash scripts/stop-pipeline.sh"
echo "  • Monitor Data: bash scripts/monitor-data-flow.sh"
echo "  • Test Pipeline: bash scripts/test-consumer.sh"
echo "  • View Logs: bash scripts/docker-logs.sh"
echo