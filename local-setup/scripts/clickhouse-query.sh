#!/bin/bash

# Default queries if no argument provided
if [ -z "$1" ]; then
  echo "Usage: ./clickhouse-query.sh <query|command>"
  echo ""
  echo "Predefined queries:"
  echo "  metrics    - Show latest sensor metrics"
  echo "  alerts     - Show recent alerts"
  echo "  hourly     - Show hourly statistics"
  echo "  status     - Show latest sensor status"
  echo "  count      - Show record counts"
  echo ""
  echo "Or provide a custom SQL query in quotes"
  echo "Example: ./clickhouse-query.sh \"SELECT COUNT(*) FROM iot.sensor_metrics\""
  exit 1
fi

case "$1" in
  metrics)
    QUERY="SELECT * FROM iot.sensor_metrics ORDER BY window_start DESC LIMIT 20 FORMAT Pretty"
    ;;
  alerts)
    QUERY="SELECT * FROM iot.sensor_alerts WHERE alert_type != 'NORMAL' ORDER BY alert_time DESC LIMIT 20 FORMAT Pretty"
    ;;
  hourly)
    QUERY="SELECT * FROM iot.sensor_hourly_stats ORDER BY hour_window DESC LIMIT 24 FORMAT Pretty"
    ;;
  status)
    QUERY="SELECT * FROM iot.sensor_latest_status ORDER BY last_update DESC LIMIT 20 FORMAT Pretty"
    ;;
  count)
    QUERY="SELECT 'sensor_metrics' as table_name, COUNT(*) as count FROM iot.sensor_metrics UNION ALL SELECT 'sensor_alerts', COUNT(*) FROM iot.sensor_alerts FORMAT Pretty"
    ;;
  *)
    QUERY="$1"
    ;;
esac

echo "Executing query..."
docker exec -it clickhouse clickhouse-client --query="$QUERY"