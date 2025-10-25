#!/bin/bash

# ================================================================================
# NUCLEAR CLEANUP - Clears ZooKeeper Completely
# ================================================================================

set -e

NAMESPACE="clickhouse"

echo "=========================================="
echo "NUCLEAR CLEANUP - ZooKeeper Reset"
echo "=========================================="
echo ""

# Get first pod
FIRST_POD=$(kubectl get pods -n "$NAMESPACE" -l clickhouse.altinity.com/app=chop -o name 2>/dev/null | head -1 | xargs basename)

if [ -z "$FIRST_POD" ]; then
    echo "ERROR: No ClickHouse pods found"
    exit 1
fi

echo "Using pod: $FIRST_POD"
echo ""

# Drop with SYNC to force ZooKeeper cleanup
echo "1. Dropping sensors_distributed ON CLUSTER SYNC..."
kubectl exec -n "$NAMESPACE" "$FIRST_POD" -- clickhouse-client --query \
    "DROP TABLE IF EXISTS benchmark.sensors_distributed ON CLUSTER 'iot-cluster' SYNC" 2>&1 || true

echo "2. Dropping cpu_distributed ON CLUSTER SYNC..."
kubectl exec -n "$NAMESPACE" "$FIRST_POD" -- clickhouse-client --query \
    "DROP TABLE IF EXISTS benchmark.cpu_distributed ON CLUSTER 'iot-cluster' SYNC" 2>&1 || true

sleep 2

echo "3. Dropping sensors_local ON CLUSTER SYNC..."
kubectl exec -n "$NAMESPACE" "$FIRST_POD" -- clickhouse-client --query \
    "DROP TABLE IF EXISTS benchmark.sensors_local ON CLUSTER 'iot-cluster' SYNC" 2>&1 || true

echo "4. Dropping cpu_local ON CLUSTER SYNC..."
kubectl exec -n "$NAMESPACE" "$FIRST_POD" -- clickhouse-client --query \
    "DROP TABLE IF EXISTS benchmark.cpu_local ON CLUSTER 'iot-cluster' SYNC" 2>&1 || true

sleep 2

# Manually clean ZooKeeper paths
echo "5. Cleaning ZooKeeper paths manually..."
kubectl exec -n "$NAMESPACE" "$FIRST_POD" -- clickhouse-client --query \
    "SYSTEM DROP REPLICA '/clickhouse/tables/0/benchmark.sensors_local' FROM ZKPATH '/clickhouse/tables/0/benchmark.sensors_local'" 2>&1 || true

kubectl exec -n "$NAMESPACE" "$FIRST_POD" -- clickhouse-client --query \
    "SYSTEM DROP REPLICA '/clickhouse/tables/1/benchmark.sensors_local' FROM ZKPATH '/clickhouse/tables/1/benchmark.sensors_local'" 2>&1 || true

kubectl exec -n "$NAMESPACE" "$FIRST_POD" -- clickhouse-client --query \
    "SYSTEM DROP REPLICA '/clickhouse/tables/2/benchmark.sensors_local' FROM ZKPATH '/clickhouse/tables/2/benchmark.sensors_local'" 2>&1 || true

kubectl exec -n "$NAMESPACE" "$FIRST_POD" -- clickhouse-client --query \
    "SYSTEM DROP REPLICA '/clickhouse/tables/0/benchmark.cpu_local' FROM ZKPATH '/clickhouse/tables/0/benchmark.cpu_local'" 2>&1 || true

kubectl exec -n "$NAMESPACE" "$FIRST_POD" -- clickhouse-client --query \
    "SYSTEM DROP REPLICA '/clickhouse/tables/1/benchmark.cpu_local' FROM ZKPATH '/clickhouse/tables/1/benchmark.cpu_local'" 2>&1 || true

kubectl exec -n "$NAMESPACE" "$FIRST_POD" -- clickhouse-client --query \
    "SYSTEM DROP REPLICA '/clickhouse/tables/2/benchmark.cpu_local' FROM ZKPATH '/clickhouse/tables/2/benchmark.cpu_local'" 2>&1 || true

sleep 2

echo ""
echo "6. Verifying cleanup..."
ALL_PODS=$(kubectl get pods -n "$NAMESPACE" -l clickhouse.altinity.com/app=chop -o name 2>/dev/null)

for POD in $ALL_PODS; do
    POD_NAME=$(basename "$POD")
    TABLES=$(kubectl exec -n "$NAMESPACE" "$POD_NAME" -- \
        clickhouse-client --query "SHOW TABLES FROM benchmark" 2>/dev/null | tr '\n' ' ' || echo "")
    
    if [ -z "$TABLES" ]; then
        echo "  ✓ $POD_NAME: clean"
    else
        echo "  ✗ $POD_NAME: $TABLES"
    fi
done

echo ""
echo "==========================================
✓ ZooKeeper paths cleared!
==========================================
"
echo "Now run: ./00-create-schema-all-replicas.sh"

