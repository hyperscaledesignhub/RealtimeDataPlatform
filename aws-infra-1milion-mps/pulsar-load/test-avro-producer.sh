#!/bin/bash

# This script demonstrates how to run the IoTPerformanceProducer with AVRO schema.

# Ensure the script is run from the pulsar-load directory
if [[ $(basename "$(pwd)") != "pulsar-load" ]]; then
  echo "Please run this script from the 'pulsar-load' directory."
  exit 1
fi

# Define the path to the pulsar-sensor-perf binary
PULSAR_SENSOR_PERF="./pulsar-sensor-perf"

# Check if the binary exists
if [ ! -f "$PULSAR_SENSOR_PERF" ]; then
  echo "Error: $PULSAR_SENSOR_PERF not found."
  exit 1
fi

# Make sure it's executable
chmod +x "$PULSAR_SENSOR_PERF"

# Define Pulsar service URL (replace with your actual URL)
PULSAR_SERVICE_URL="pulsar://localhost:6650"
# Define a topic for AVRO messages
AVRO_TOPIC="persistent://public/default/iot-sensor-data-avro"

echo "======================================================"
echo "🚀 Testing IoTPerformanceProducer with AVRO Schema"
echo "======================================================"
echo ""

echo "1. Running AVRO Producer with built-in schema..."
echo "   (Sending 100 messages at 10 msg/s to $AVRO_TOPIC)"
$PULSAR_SENSOR_PERF iot-produce \
  --service-url "$PULSAR_SERVICE_URL" \
  --topics "$AVRO_TOPIC" \
  --rate 10 \
  --num-messages 100 \
  --use-avro \
  --warmup-time 0 \
  --stats-interval-seconds 5

if [ $? -eq 0 ]; then
  echo "✅ AVRO Producer test completed successfully."
else
  echo "❌ AVRO Producer test failed."
  exit 1
fi
echo ""

echo "======================================================"
echo "✅ All AVRO Producer tests finished."
echo "======================================================"
echo ""
echo "Next steps:"
echo "  - To consume these messages, you would need an AVRO consumer."
echo "  - Example: pulsar-client consume -s my-sub -n 0 $AVRO_TOPIC --schema-type AVRO"
echo "  - Or a custom Java consumer using Pulsar's Schema API for AVRO."
