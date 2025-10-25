#!/bin/bash

echo "=== REAL-TIME DATA FLOW MONITOR ==="
echo "Press Ctrl+C to stop monitoring"
echo

while true; do
    clear
    echo "=== IoT Data Pipeline Status - $(date) ==="
    echo
    
    # Get current counts
    SENSOR_COUNT=$(docker exec clickhouse clickhouse-client --query="SELECT COUNT(*) FROM iot.sensor_raw_data" 2>/dev/null)
    ALERT_COUNT=$(docker exec clickhouse clickhouse-client --query="SELECT COUNT(*) FROM iot.sensor_alerts" 2>/dev/null)
    
    echo "📊 Current Data Counts:"
    echo "   • Sensor Records: $SENSOR_COUNT"
    echo "   • Alert Records: $ALERT_COUNT"
    echo
    
    echo "🔥 Latest 3 Sensor Readings:"
    docker exec clickhouse clickhouse-client --query="
    SELECT 
        concat('   • ', sensor_id, ': ', toString(temperature), '°C, ', toString(humidity), '% humidity, ', toString(battery_level), '% battery')
    FROM iot.sensor_raw_data 
    ORDER BY timestamp DESC 
    LIMIT 3
    " 2>/dev/null
    
    echo
    echo "🚨 Recent Alerts:"
    RECENT_ALERTS=$(docker exec clickhouse clickhouse-client --query="
    SELECT 
        concat('   • ', sensor_id, ' - ', alert_type, ' (', toString(temperature), '°C)')
    FROM iot.sensor_alerts 
    ORDER BY alert_time DESC 
    LIMIT 3
    " 2>/dev/null)
    
    if [ -z "$RECENT_ALERTS" ]; then
        echo "   • No recent alerts"
    else
        echo "$RECENT_ALERTS"
    fi
    
    echo
    echo "⏱️  Refreshing in 5 seconds..."
    sleep 5
done