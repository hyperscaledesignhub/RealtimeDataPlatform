# IoT Data Pipeline

Complete data pipeline for ingesting IoT sensor data using Apache Pulsar, processing with Apache Flink (including Flink SQL), and storing in ClickHouse.

## Architecture

```
IoT Sensors → Pulsar → Flink (Stream Processing + SQL) → ClickHouse
```

## Components

### 1. IoT Data Producer
- Generates simulated sensor data (temperature, humidity, pressure, battery)
- Publishes to Apache Pulsar topic
- Configurable data generation rate

### 2. Apache Pulsar
- Message broker for reliable data ingestion
- Handles backpressure and message persistence
- Topic: `persistent://public/default/iot-sensor-data`

### 3. Apache Flink Consumer
- Consumes data from Pulsar
- Performs stream processing with Flink SQL:
  - Windowed aggregations (1-minute tumbling windows)
  - Alert detection (temperature > 35°C, humidity > 80%, battery < 20%)
  - Real-time metrics calculation

### 4. ClickHouse
- Time-series database for storing processed data
- Tables:
  - `sensor_metrics`: Aggregated sensor metrics
  - `sensor_alerts`: Alert events
  - `sensor_raw_data`: Raw sensor readings
- Materialized views for hourly aggregations

## Data Schema

```java
SensorData {
  sensorId: String
  sensorType: String
  location: String
  temperature: Double
  humidity: Double
  pressure: Double
  batteryLevel: Double
  status: String
  timestamp: Instant
  metadata: {
    manufacturer: String
    model: String
    firmwareVersion: String
    latitude: Double
    longitude: Double
  }
}
```

## Quick Start

### Prerequisites
- Java 11+
- Maven 3.6+
- Docker & Docker Compose

### Build and Run

1. Build the components:
```bash
mvn clean package
```

2. Start the pipeline:
```bash
chmod +x scripts/start-pipeline.sh
./scripts/start-pipeline.sh
```

3. Access the services:
- Pulsar Admin: http://localhost:8080
- Flink UI: http://localhost:8081
- ClickHouse: http://localhost:8123
- Grafana: http://localhost:3000

### Query ClickHouse

```sql
-- View latest sensor metrics
SELECT * FROM iot.sensor_metrics ORDER BY window_start DESC LIMIT 10;

-- View alerts
SELECT * FROM iot.sensor_alerts WHERE alert_type != 'NORMAL' ORDER BY alert_time DESC;

-- Get hourly statistics
SELECT * FROM iot.sensor_hourly_stats ORDER BY hour_window DESC LIMIT 24;
```

## Configuration

Environment variables:
- `PULSAR_URL`: Pulsar broker URL (default: pulsar://localhost:6650)
- `PULSAR_TOPIC`: Topic name (default: persistent://public/default/iot-sensor-data)
- `CLICKHOUSE_URL`: ClickHouse JDBC URL (default: jdbc:clickhouse://localhost:8123/iot)

## Monitoring

- Flink Web UI provides job metrics and backpressure monitoring
- Grafana dashboards for visualizing sensor data
- ClickHouse system tables for query performance

## Scaling

- Increase Flink parallelism in `FlinkIoTProcessor.java`
- Scale Pulsar partitions for higher throughput
- Add ClickHouse shards for horizontal scaling