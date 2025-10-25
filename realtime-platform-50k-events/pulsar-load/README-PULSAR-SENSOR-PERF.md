# Pulsar Sensor Performance Producer

This directory contains the `pulsar-sensor-perf` binary for generating IoT sensor data with device ID range control.

## Files

- `pulsar-sensor-perf` - Main executable binary
- `IOT_PRODUCER_USAGE.md` - Detailed usage documentation
- `test-iot-producer.sh` - Test script
- `target/` - Compiled classes and dependencies

## Quick Start

```bash
# Show help
./pulsar-sensor-perf iot-produce --help

# Basic usage with device range 1-1000 and 250K messages/sec
./pulsar-sensor-perf iot-produce \
  --device-id-min 1 --device-id-max 1000 \
  --rate 250000 \
  --topics persistent://public/default/iot-sensor-data \
  --service-url pulsar://localhost:6650

# Custom device prefix and types
./pulsar-sensor-perf iot-produce \
  --device-id-min 1 --device-id-max 500 \
  --device-prefix "sensor" \
  --device-types "temperature_sensor,humidity_sensor" \
  --rate 100000 \
  --topics persistent://public/default/iot-sensor-data \
  --service-url pulsar://localhost:6650
```

## Key Features

- **Device ID Range Control**: Specify min/max device IDs
- **Distributed Message Rate**: Rate is distributed across all devices
- **IoT Sensor Data**: Generates realistic sensor readings
- **Flink Compatible**: Messages match Flink benchmark schema

## Device ID Distribution

When you specify a device ID range (e.g., 1-1000) and a message rate (e.g., 250K), the producer will:
- Use ALL devices in the range (1, 2, 3, ..., 1000)
- Distribute the total rate evenly across all devices
- Each device will send approximately 250 messages/second

For more details, see `IOT_PRODUCER_USAGE.md`.
