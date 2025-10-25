# Docker Setup for AVRO-enabled IoT Performance Producer

## Overview
The Dockerfile.perf has been updated to support AVRO serialization format by default for the IoT Performance Producer.

## Changes Made

### 1. Updated pom.xml
- Added AVRO dependency (`org.apache.avro:avro:1.12.0`)
- Added AVRO Maven plugin for schema generation
- Updated Pulsar version to 4.1.1

### 2. Added AVRO Schema
- Created `src/main/resources/avro/SensorData.avsc`
- Schema includes nested metadata structure for IoT sensor data

### 3. Updated Dockerfile.perf
- Set `USE_AVRO="true"` by default
- Added `--use-avro` flag to the default CMD
- Updated documentation to reflect AVRO as default format

### 4. Updated Dependencies
- Copied the latest libs directory (renamed from target) with AVRO-enabled IoTPerformanceProducer
- Updated pulsar-sensor-perf script
- **Note**: The compiled libraries are stored in `libs/` directory instead of `target/` to allow Git tracking

## Usage

### Build the Docker Image
```bash
cd /Users/vijayabhaskarv/IOT/datapipeline-0/Flink-Benchmark/high_infra_flink/producer-load
docker build -f Dockerfile.perf -t iot-producer-avro .
```

### Run with Default Settings (AVRO)
```bash
docker run iot-producer-avro
```

### Run with Custom Topic
```bash
docker run iot-producer-avro "persistent://public/default/my-custom-topic"
```

### Override Environment Variables
```bash
docker run -e MESSAGE_RATE=500 -e NUM_MESSAGES=1000 iot-producer-avro
```

## Environment Variables
- `PULSAR_URL`: Pulsar service URL (default: pulsar://localhost:6650)
- `PULSAR_TOPIC`: Target topic name (default: persistent://public/default/iot-sensor-data)
- `MESSAGE_RATE`: Messages per second (default: 1000)
- `NUM_MESSAGES`: Total messages to send (default: 0 = unlimited)
- `DEVICE_ID_MIN`: Minimum device ID (default: 1)
- `DEVICE_ID_MAX`: Maximum device ID (default: 100000)
- `STATS_INTERVAL`: Stats reporting interval in seconds (default: 10)

## AVRO Schema Structure
The producer uses the built-in SensorData.avsc schema with the following structure:
```json
{
  "type": "record",
  "name": "SensorData",
  "namespace": "org.apache.pulsar.testclient.avro",
  "fields": [
    {"name": "sensorId", "type": "string"},
    {"name": "sensorType", "type": "string"},
    {"name": "location", "type": "string"},
    {"name": "temperature", "type": "double"},
    {"name": "humidity", "type": "double"},
    {"name": "pressure", "type": "double"},
    {"name": "batteryLevel", "type": "double"},
    {"name": "status", "type": "string"},
    {"name": "timestamp", "type": {"type": "long", "logicalType": "timestamp-millis"}},
    {"name": "metadata", "type": {
      "type": "record",
      "name": "MetaData",
      "fields": [
        {"name": "manufacturer", "type": "string"},
        {"name": "model", "type": "string"},
        {"name": "firmwareVersion", "type": "string"},
        {"name": "latitude", "type": "double"},
        {"name": "longitude", "type": "double"}
      ]
    }}
  ]
}
```

## Verification
The container will automatically:
1. Load the AVRO schema on startup
2. Create producers with AVRO serialization
3. Send properly formatted AVRO messages to the specified topic
4. Display performance metrics

Expected output includes:
```
🔧 IoT Performance Producer Configuration:
   📋 Schema Type: AVRO
   📄 Schema File: built-in SensorData.avsc
```

## Status: ✅ READY
All changes have been applied and the Docker setup is ready for AVRO-enabled IoT data production.
