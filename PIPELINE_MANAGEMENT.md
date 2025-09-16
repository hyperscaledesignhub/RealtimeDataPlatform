# 🚀 IoT Data Pipeline Management

## Quick Start Commands

### 🎯 Essential Commands
```bash
# Start the complete pipeline
bash scripts/start-pipeline.sh

# Check pipeline status  
bash scripts/status-pipeline.sh

# Stop the complete pipeline
bash scripts/stop-pipeline.sh
```

### 📊 Monitoring Commands
```bash
# Real-time data monitoring
bash scripts/monitor-data-flow.sh

# Test pipeline end-to-end
bash scripts/test-consumer.sh

# Check container logs
bash scripts/docker-logs.sh
```

## 🏗️ Pipeline Architecture

**Data Flow:** IoT Producer → Pulsar → Flink Consumer → ClickHouse

- **IoT Producer**: Generates sensor data every second
- **Pulsar**: Message broker for streaming data
- **Flink**: Stream processing with real-time alerts  
- **ClickHouse**: Time-series database for analytics

## 🔍 Access Points

- **Flink Dashboard**: http://localhost:8081
- **Pulsar Admin UI**: http://localhost:8080  
- **ClickHouse HTTP**: http://localhost:8123

## 📈 Manual Data Queries

```bash
# Check record counts
docker exec clickhouse clickhouse-client --query="SELECT COUNT(*) FROM iot.sensor_raw_data"

# View recent data
docker exec clickhouse clickhouse-client --query="SELECT sensor_id, temperature, timestamp FROM iot.sensor_raw_data ORDER BY timestamp DESC LIMIT 5"

# Check alerts
docker exec clickhouse clickhouse-client --query="SELECT sensor_id, alert_type, temperature FROM iot.sensor_alerts ORDER BY alert_time DESC LIMIT 5"
```

## 🛠️ Troubleshooting

### If Pipeline Fails to Start:
1. Stop any existing containers: `bash scripts/stop-pipeline.sh`  
2. Clean Docker: `docker system prune -f`
3. Restart: `bash scripts/start-pipeline.sh`

### If No Data is Flowing:
1. Check status: `bash scripts/status-pipeline.sh`
2. Check Flink job: Visit http://localhost:8081
3. View logs: `bash scripts/docker-logs.sh`

## ⚡ Performance Metrics

- **Throughput**: ~60-80 messages/minute
- **Latency**: <5 seconds end-to-end  
- **Storage**: Time-series optimized with TTL policies
- **Alerts**: Real-time detection for temperature/humidity/battery thresholds