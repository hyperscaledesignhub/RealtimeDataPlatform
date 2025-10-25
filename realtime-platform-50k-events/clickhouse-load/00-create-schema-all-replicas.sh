#!/bin/bash

# ================================================================================
# Create ClickHouse Schema Across All Replicas
# ================================================================================
# This script creates the benchmark database and tables on all ClickHouse replicas
# Prerequisites:
#   - ClickHouse cluster is running
#   - kubectl is configured for the EKS cluster
# ================================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="clickhouse"
SCHEMA_FILE="01-create-schema.sql"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}ClickHouse Schema Creation${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if schema file exists
if [ ! -f "$SCHEMA_FILE" ]; then
    echo -e "${RED}ERROR: Schema file not found: $SCHEMA_FILE${NC}"
    echo "Please run this script from the clickhouse-load directory"
    exit 1
fi

# Get all ClickHouse pods
echo -e "${YELLOW}==> Finding ClickHouse pods...${NC}"
PODS=$(kubectl get pods -n "$NAMESPACE" -l clickhouse.altinity.com/app=chop -o name 2>/dev/null)

if [ -z "$PODS" ]; then
    echo -e "${RED}ERROR: No ClickHouse pods found in namespace: $NAMESPACE${NC}"
    echo "Please ensure ClickHouse is deployed"
    exit 1
fi

POD_COUNT=$(echo "$PODS" | wc -l | tr -d ' ')
echo -e "${GREEN}✓ Found $POD_COUNT ClickHouse replicas${NC}"

# List all pods
echo ""
echo "ClickHouse pods:"
for POD in $PODS; do
    POD_NAME=$(basename "$POD")
    POD_STATUS=$(kubectl get pod -n "$NAMESPACE" "$POD_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    if [ "$POD_STATUS" = "Running" ]; then
        echo -e "  ${GREEN}✓${NC} $POD_NAME ($POD_STATUS)"
    else
        echo -e "  ${YELLOW}⚠${NC} $POD_NAME ($POD_STATUS)"
    fi
done
echo ""

# Wait for all pods to be ready
echo -e "${YELLOW}==> Waiting for all pods to be ready...${NC}"
for POD in $PODS; do
    POD_NAME=$(basename "$POD")
    kubectl wait --for=condition=Ready pod/"$POD_NAME" -n "$NAMESPACE" --timeout=60s 2>/dev/null || true
done
echo -e "${GREEN}✓ All pods checked${NC}"
echo ""

# Create schema on each replica
SUCCESS_COUNT=0
FAIL_COUNT=0

for POD in $PODS; do
    POD_NAME=$(basename "$POD")
    echo -e "${BLUE}==> Processing: $POD_NAME${NC}"
    
    # Create database
    echo "   Creating database..."
    if kubectl exec -n "$NAMESPACE" "$POD_NAME" -- \
        clickhouse-client --query "CREATE DATABASE IF NOT EXISTS benchmark" 2>/dev/null; then
        echo -e "   ${GREEN}✓ Database created${NC}"
    else
        echo -e "   ${RED}✗ Failed to create database${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo ""
        continue
    fi
    
    # Create tables (suppress stderr to avoid clutter from "already exists" messages)
    echo "   Creating tables..."
    ERROR_OUTPUT=$(cat "$SCHEMA_FILE" | kubectl exec -i -n "$NAMESPACE" "$POD_NAME" -- \
        clickhouse-client --multiquery 2>&1) || true
    
    if echo "$ERROR_OUTPUT" | grep -q "DB::Exception" && ! echo "$ERROR_OUTPUT" | grep -q "already exists"; then
        echo -e "   ${RED}✗ Error creating tables:${NC}"
        echo "$ERROR_OUTPUT" | head -3
    else
        echo -e "   ${GREEN}✓ Tables created/verified${NC}"
    fi
    
    # Verify tables exist
    echo "   Verifying tables..."
    TABLES=$(kubectl exec -n "$NAMESPACE" "$POD_NAME" -- \
        clickhouse-client --query "SHOW TABLES FROM benchmark" 2>/dev/null | tr '\n' ' ' || echo "")
    
    # Check for specific tables
    HAS_CPU_LOCAL=$(echo "$TABLES" | grep -q "cpu_local" && echo "yes" || echo "no")
    HAS_CPU_DIST=$(echo "$TABLES" | grep -q "cpu_distributed" && echo "yes" || echo "no")
    HAS_SENSORS_LOCAL=$(echo "$TABLES" | grep -q "sensors_local" && echo "yes" || echo "no")
    HAS_SENSORS_DIST=$(echo "$TABLES" | grep -q "sensors_distributed" && echo "yes" || echo "no")
    
    MISSING_TABLES=""
    [ "$HAS_CPU_LOCAL" = "no" ] && MISSING_TABLES="$MISSING_TABLES cpu_local"
    [ "$HAS_CPU_DIST" = "no" ] && MISSING_TABLES="$MISSING_TABLES cpu_distributed"
    [ "$HAS_SENSORS_LOCAL" = "no" ] && MISSING_TABLES="$MISSING_TABLES sensors_local"
    [ "$HAS_SENSORS_DIST" = "no" ] && MISSING_TABLES="$MISSING_TABLES sensors_distributed"
    
    if [ -z "$MISSING_TABLES" ]; then
        echo -e "   ${GREEN}✓ All tables present: cpu_local, cpu_distributed, sensors_local, sensors_distributed${NC}"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo -e "   ${YELLOW}⚠ Missing tables:$MISSING_TABLES${NC}"
        echo -e "   ${YELLOW}  Present tables: $TABLES${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    
    echo ""
done

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Schema Creation Summary${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Total replicas: $POD_COUNT"
echo -e "${GREEN}Successful: $SUCCESS_COUNT${NC}"
if [ $FAIL_COUNT -gt 0 ]; then
    echo -e "${RED}Failed: $FAIL_COUNT${NC}"
fi
echo ""

# Detailed verification across all replicas
echo -e "${BLUE}Detailed Table Verification:${NC}"
echo ""
printf "%-45s %-15s %-15s %-15s %-15s\n" "POD NAME" "cpu_local" "cpu_dist" "sensors_local" "sensors_dist"
echo "------------------------------------------------------------------------------------------------------"

for POD in $PODS; do
    POD_NAME=$(basename "$POD")
    
    # Check for cpu_local
    if kubectl exec -n "$NAMESPACE" "$POD_NAME" -- \
        clickhouse-client --query "EXISTS TABLE benchmark.cpu_local" 2>/dev/null | grep -q "1"; then
        CPU_LOCAL="${GREEN}✓${NC}"
    else
        CPU_LOCAL="${RED}✗${NC}"
    fi
    
    # Check for cpu_distributed
    if kubectl exec -n "$NAMESPACE" "$POD_NAME" -- \
        clickhouse-client --query "EXISTS TABLE benchmark.cpu_distributed" 2>/dev/null | grep -q "1"; then
        CPU_DIST="${GREEN}✓${NC}"
    else
        CPU_DIST="${RED}✗${NC}"
    fi
    
    # Check for sensors_local
    if kubectl exec -n "$NAMESPACE" "$POD_NAME" -- \
        clickhouse-client --query "EXISTS TABLE benchmark.sensors_local" 2>/dev/null | grep -q "1"; then
        SENSORS_LOCAL="${GREEN}✓${NC}"
    else
        SENSORS_LOCAL="${RED}✗${NC}"
    fi
    
    # Check for sensors_distributed
    if kubectl exec -n "$NAMESPACE" "$POD_NAME" -- \
        clickhouse-client --query "EXISTS TABLE benchmark.sensors_distributed" 2>/dev/null | grep -q "1"; then
        SENSORS_DIST="${GREEN}✓${NC}"
    else
        SENSORS_DIST="${RED}✗${NC}"
    fi
    
    printf "%-45s %-22s %-22s %-22s %-22s\n" "$POD_NAME" \
        "$(echo -e "$CPU_LOCAL")" \
        "$(echo -e "$CPU_DIST")" \
        "$(echo -e "$SENSORS_LOCAL")" \
        "$(echo -e "$SENSORS_DIST")"
done

echo ""

# Sample schema from first replica
echo -e "${BLUE}Schema details from first replica:${NC}"
FIRST_POD=$(echo "$PODS" | head -1 | xargs basename)
kubectl exec -n "$NAMESPACE" "$FIRST_POD" -- clickhouse-client --query \
    "SELECT name, engine, total_rows FROM system.tables WHERE database = 'benchmark' FORMAT Pretty" 2>/dev/null || true

echo ""

# Final verdict
if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ SUCCESS!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Schema created successfully on all $POD_COUNT replicas!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Start Flink job to consume from Pulsar"
    echo "  2. Monitor data flow in Grafana dashboards"
    exit 0
else
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}⚠ WARNING${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}Schema creation completed with issues on $FAIL_COUNT/$POD_COUNT replicas${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Check pod logs: kubectl logs -n $NAMESPACE <pod-name>"
    echo "  2. Check ClickHouse cluster status"
    echo "  3. Re-run this script after fixing issues"
    exit 1
fi

