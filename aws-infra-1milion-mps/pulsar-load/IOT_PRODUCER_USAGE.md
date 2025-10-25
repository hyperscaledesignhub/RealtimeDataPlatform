# IoT Performance Producer Usage Guide

## Overview

The `IoTPerformanceProducer` is an enhanced version of the Pulsar PerformanceProducer specifically designed for IoT sensor data generation compatible with the Flink benchmark pipeline. It generates realistic sensor data messages with device ID range control and distributed message rates.

## Key Features

- **Device ID Range Control**: Specify min/max device IDs (e.g., 1-1000)
- **Distributed Message Rate**: Messages are distributed across all devices in the range
- **SensorData Compatibility**: Generates messages matching the Flink benchmark schema
- **Realistic IoT Data**: Temperature, humidity, pressure, CO2, noise, light, motion, etc.
- **Performance Metrics**: Full latency and throughput reporting

## Usage Examples

### Basic Usage - 1000 devices, 250K msg/sec

```bash
# Generate messages from devices 1-1000 at 250K msg/sec
./pulsar-perf iot-produce \
  --device-id-min 1 \
  --device-id-max 1000 \
  --rate 250000 \
  --topics persistent://public/default/iot-sensor-data \
  --num-producers 4 \
  --threads 4
```

### High-Volume Test - 10K devices, 1M msg/sec

```bash
# Generate messages from devices 1-10000 at 1M msg/sec
./pulsar-perf iot-produce \
  --device-id-min 1 \
  --device-id-max 10000 \
  --rate 1000000 \
  --topics persistent://public/default/iot-sensor-data \
  --num-producers 8 \
  --threads 8 \
  --compression LZ4
```

### Custom Device Types and Configuration

```bash
# Custom device types and configuration
./pulsar-perf iot-produce \
  --device-id-min 100 \
  --device-id-max 500 \
  --device-prefix "sensor" \
  --device-types "temperature_sensor,humidity_sensor,pressure_sensor,motion_sensor" \
  --rate 50000 \
  --topics persistent://public/default/iot-sensor-data \
  --num-customers 500 \
  --num-sites 50 \
  --compression LZ4 \
  --batch-time-window 5.0 \
  --batch-max-messages 200
```

### Performance Testing with Duration

```bash
# Run for 5 minutes with specific device range
./pulsar-perf iot-produce \
  --device-id-min 1 \
  --device-id-max 5000 \
  --rate 100000 \
  --test-duration 300 \
  --topics persistent://public/default/iot-sensor-data \
  --num-producers 4 \
  --threads 4 \
  --compression LZ4 \
  --histogram-file latency-stats.hdr
```

## Command Line Options

### Device ID Control
- `--device-id-min`: Minimum device ID in range (default: 1)
- `--device-id-max`: Maximum device ID in range (default: 1000)
- `--device-prefix`: Device ID prefix (default: "dev")

### IoT Configuration
- `--num-customers`: Number of customer IDs to generate (default: 1000)
- `--num-sites`: Number of site IDs to generate (default: 100)
- `--device-types`: Comma-separated list of device types (default: "temperature_sensor,humidity_sensor,pressure_sensor,motion_sensor,light_sensor,co2_sensor,noise_sensor,multisensor")

### Performance Options
- `--rate`: Publish rate msg/s across topics (default: 100)
- `--threads`: Number of test threads (default: 1)
- `--num-producers`: Number of producers per topic (default: 1)
- `--num-messages`: Total messages to publish (0 = unlimited)
- `--test-duration`: Test duration in seconds (0 = unlimited)
- `--compression`: Compression type (NONE, LZ4, ZLIB, ZSTD, SNAPPY)
- `--batch-time-window`: Batch messages in ms window (default: 1.0)
- `--batch-max-messages`: Maximum messages per batch (default: 1000)
- `--batch-max-bytes`: Maximum bytes per batch (default: 4MB)

### Standard Options
- `--topics`: Comma-separated list of topics
- `--service-url`: Pulsar service URL
- `--admin-url`: Pulsar admin URL
- `--producer-name`: Producer name prefix
- `--max-outstanding`: Max outstanding messages
- `--send-timeout`: Send timeout in seconds
- `--warmup-time`: Warm-up time in seconds

## Message Format

The producer generates JSON messages with the following structure:

```json
{
  "deviceId": "dev-0000001",
  "deviceType": "temperature_sensor",
  "customerId": "cust-000001",
  "siteId": "site-00001",
  "latitude": 37.7749,
  "longitude": -122.4194,
  "altitude": 100.5,
  "time": "2024-01-15T10:30:45.123Z",
  "temperature": 22.5,
  "humidity": 65.2,
  "pressure": 1013.25,
  "co2Level": 450.0,
  "noiseLevel": 45.3,
  "lightLevel": 250.7,
  "motionDetected": 0,
  "batteryLevel": 85.2,
  "signalStrength": -65.4,
  "memoryUsage": 45.8,
  "cpuUsage": 12.3,
  "status": 1,
  "errorCount": 0,
  "packetsSent": 1250,
  "packetsReceived": 1180,
  "bytesSent": 1500000,
  "bytesReceived": 1416000
}
```

## Performance Considerations

### Device Distribution
- Messages are randomly distributed across all devices in the specified range
- Each device gets approximately `rate / (device-id-max - device-id-min + 1)` messages per second
- For 250K msg/sec with devices 1-1000: ~250 messages per device per second

### Scaling Recommendations
- Use multiple threads (`--threads`) for higher throughput
- Use multiple producers per topic (`--num-producers`) for better parallelism
- Enable compression (`--compression LZ4`) for network efficiency
- Adjust batch settings for optimal performance

### Example Scaling
```bash
# For 1M msg/sec with 10K devices
./pulsar-perf iot-produce \
  --device-id-min 1 \
  --device-id-max 10000 \
  --rate 1000000 \
  --threads 8 \
  --num-producers 4 \
  --compression LZ4 \
  --batch-time-window 2.0 \
  --batch-max-messages 500
```

## Integration with Flink Benchmark

This producer is designed to work seamlessly with the Flink benchmark pipeline:

1. **Topic**: Use `persistent://public/default/iot-sensor-data`
2. **Message Format**: JSON SensorData compatible with Flink deserialization
3. **Device ID**: Used as message key for proper partitioning
4. **Rate Control**: Distributed across device range for realistic load

## Monitoring

The producer provides comprehensive metrics:
- Messages per second
- Throughput in Mbit/s
- Latency percentiles (mean, median, 95th, 99th, 99.9th, 99.99th)
- Failure rates
- HDR histogram output (optional)

Use `--histogram-file` to save detailed latency statistics for analysis.
