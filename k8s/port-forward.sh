#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting port-forward for all services...${NC}"
echo "========================================"

# Kill any existing port-forward processes
echo -e "${YELLOW}Stopping any existing port-forwards...${NC}"
pkill -f "kubectl port-forward" 2>/dev/null

# Start port-forwards in background
echo -e "\n${YELLOW}Starting Pulsar Admin UI port-forward...${NC}"
kubectl port-forward -n iot-pipeline svc/pulsar 8080:8080 &
PULSAR_PID=$!
echo "Pulsar Admin UI will be available at: http://localhost:8080"

echo -e "\n${YELLOW}Starting ClickHouse port-forward...${NC}"
kubectl port-forward -n iot-pipeline svc/clickhouse 8123:8123 &
CLICKHOUSE_PID=$!
echo "ClickHouse will be available at: http://localhost:8123"

echo -e "\n${YELLOW}Starting Flink UI port-forward...${NC}"
kubectl port-forward -n iot-pipeline svc/flink-jobmanager 8081:8081 &
FLINK_PID=$!
echo "Flink UI will be available at: http://localhost:8081"

echo -e "\n${GREEN}All port-forwards started!${NC}"
echo "PIDs: Pulsar=$PULSAR_PID, ClickHouse=$CLICKHOUSE_PID, Flink=$FLINK_PID"
echo ""
echo "Press Ctrl+C to stop all port-forwards..."

# Wait for Ctrl+C
trap "echo -e '\n${YELLOW}Stopping port-forwards...${NC}'; kill $PULSAR_PID $CLICKHOUSE_PID $FLINK_PID 2>/dev/null; exit" INT

# Keep script running
while true; do
    sleep 1
done