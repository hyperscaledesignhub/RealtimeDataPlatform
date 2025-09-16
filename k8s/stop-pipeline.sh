#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${RED}Stopping IoT Pipeline...${NC}"
echo "========================"

# Set kubeconfig for Kind cluster
export KUBECONFIG=/tmp/iot-kubeconfig

# Check if cluster exists
if ! kubectl get nodes &>/dev/null; then
    echo -e "${RED}Error: Kind cluster 'iot-pipeline' not found or not accessible${NC}"
    echo "Make sure the cluster is running and KUBECONFIG is set correctly"
    exit 1
fi

# Stop all services
echo -e "\n${YELLOW}Stopping all services...${NC}"

# Delete all resources in the namespace
kubectl delete namespace iot-pipeline --timeout=60s 2>/dev/null || true

# Wait for namespace deletion
echo -e "${YELLOW}Waiting for namespace deletion...${NC}"
kubectl wait --for=delete namespace/iot-pipeline --timeout=60s 2>/dev/null || true

# Kill any port-forward processes
echo -e "\n${YELLOW}Stopping port-forward processes...${NC}"
pkill -f "kubectl port-forward" 2>/dev/null || true

echo -e "\n${GREEN}Pipeline stopped successfully!${NC}"
echo "=============================="
echo -e "\n${YELLOW}To start the pipeline again, run:${NC}"
echo "./start-pipeline.sh"