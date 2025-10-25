#!/bin/bash

# Script to set PARTITION_INDEX based on pod name
# This script extracts the partition index from the pod name
# Pod names: iot-flink-job-partitioned-taskmanager-0, iot-flink-job-partitioned-taskmanager-1, etc.

# Get pod name from environment or use default
POD_NAME=${HOSTNAME:-"iot-flink-job-partitioned-taskmanager-0"}

# Extract partition index from pod name
# Format: iot-flink-job-partitioned-taskmanager-0 -> 0
# Format: iot-flink-job-partitioned-taskmanager-1 -> 1
PARTITION_INDEX=$(echo "$POD_NAME" | sed 's/.*taskmanager-\([0-9]*\)/\1/')

# If extraction failed, default to 0
if [ -z "$PARTITION_INDEX" ] || ! [[ "$PARTITION_INDEX" =~ ^[0-9]+$ ]]; then
    PARTITION_INDEX=0
fi

echo "Pod Name: $POD_NAME"
echo "Partition Index: $PARTITION_INDEX"

# Export the partition index for the Flink job
export PARTITION_INDEX

# Start the Flink task manager with the partition index
exec "$@"
