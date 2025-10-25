#!/bin/bash

# Entrypoint script for IoT Performance Producer with device ID distribution
# Calculates device ID ranges based on Kubernetes pod instance

# Get the total device count from environment variable
TOTAL_DEVICES=${TOTAL_DEVICE_COUNT:-17000}

# Get the number of replicas (instances) from environment variable
# This should be set in the Kubernetes deployment
NUM_REPLICAS=${NUM_REPLICAS:-1}

# Calculate device ID range per instance
DEVICES_PER_INSTANCE=$((TOTAL_DEVICES / NUM_REPLICAS))
REMAINDER=$((TOTAL_DEVICES % NUM_REPLICAS))

# Get the current instance number (0-based)
# For StatefulSet: pod names are predictable (iot-perf-producer-0, iot-perf-producer-1, etc.)
if [ -n "${POD_NAME}" ]; then
    # Extract ordinal number from StatefulSet pod name
    # Format: iot-perf-producer-0, iot-perf-producer-1, iot-perf-producer-2
    INSTANCE_NUM=$(echo "${POD_NAME}" | grep -o '[0-9]*$')
    if [ -z "${INSTANCE_NUM}" ]; then
        INSTANCE_NUM=0
    fi
else
    # Fallback to environment variable
    INSTANCE_NUM=${INSTANCE_NUM:-0}
fi

# Calculate device ID range for this instance
DEVICE_ID_MIN=$((INSTANCE_NUM * DEVICES_PER_INSTANCE + 1))

# Handle remainder distribution (give extra devices to first few instances)
if [ $INSTANCE_NUM -lt $REMAINDER ]; then
    DEVICE_ID_MAX=$((DEVICE_ID_MIN + DEVICES_PER_INSTANCE))
else
    DEVICE_ID_MAX=$((DEVICE_ID_MIN + DEVICES_PER_INSTANCE - 1))
fi

# Ensure we don't exceed total device count
if [ $DEVICE_ID_MAX -gt $TOTAL_DEVICES ]; then
    DEVICE_ID_MAX=$TOTAL_DEVICES
fi

# Build the command arguments
ARGS=()

# Add basic arguments
ARGS+=("--service-url" "${PULSAR_URL}")
ARGS+=("--rate" "${MESSAGE_RATE}")
ARGS+=("--device-id-min" "${DEVICE_ID_MIN}")
ARGS+=("--device-id-max" "${DEVICE_ID_MAX}")
ARGS+=("--num-messages" "${NUM_MESSAGES}")
ARGS+=("--stats-interval-seconds" "${STATS_INTERVAL}")

# Add AVRO options if enabled
if [ "${USE_AVRO}" = "true" ]; then
    ARGS+=("--use-avro")
    
    # Add custom schema file if specified
    if [ -n "${SCHEMA_FILE}" ]; then
        ARGS+=("--schema-file" "${SCHEMA_FILE}")
    fi
    
    # Add schema registry URL if specified
    if [ -n "${SCHEMA_REGISTRY_URL}" ]; then
        ARGS+=("--schema-registry-url" "${SCHEMA_REGISTRY_URL}")
    fi
fi

# Add any additional arguments passed to the container
ARGS+=("$@")

# Log the configuration for this instance
echo "🚀 IoT Performance Producer - Instance Configuration:"
echo "   📊 Total Devices: ${TOTAL_DEVICES}"
echo "   🔢 Total Instances: ${NUM_REPLICAS}"
echo "   🏷️  Instance Number: ${INSTANCE_NUM}"
echo "   📱 Device ID Range: ${DEVICE_ID_MIN} to ${DEVICE_ID_MAX} ($(($DEVICE_ID_MAX - $DEVICE_ID_MIN + 1)) devices)"
echo "   📡 Pulsar URL: ${PULSAR_URL}"
echo "   📋 Schema Type: ${USE_AVRO:-false}"
echo ""

# Execute the pulsar-sensor-perf with the built arguments
exec /app/pulsar-sensor-perf "${ARGS[@]}"
