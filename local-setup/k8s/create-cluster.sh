#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}Creating Kind Kubernetes Cluster for IoT Pipeline...${NC}"
echo "=================================================="

# Check if kind is installed
if ! command -v kind &> /dev/null; then
    echo -e "${RED}Error: kind is not installed${NC}"
    echo "Install kind: brew install kind (Mac) or check https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
    exit 1
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed${NC}"
    echo "Install kubectl: brew install kubectl (Mac)"
    exit 1
fi

# Check if cluster already exists
if kind get clusters 2>/dev/null | grep -q "iot-pipeline"; then
    echo -e "${YELLOW}Kind cluster 'iot-pipeline' already exists.${NC}"
    read -p "Do you want to delete and recreate it? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Deleting existing cluster...${NC}"
        kind delete cluster --name iot-pipeline
        # Clean up kubeconfig
        rm -f /tmp/iot-kubeconfig
    else
        echo -e "${BLUE}Using existing cluster. Setting up kubeconfig...${NC}"
        kind get kubeconfig --name iot-pipeline > /tmp/iot-kubeconfig
        export KUBECONFIG=/tmp/iot-kubeconfig
        echo -e "${GREEN}Cluster is ready!${NC}"
        kubectl get nodes
        echo -e "\n${BLUE}To start the pipeline, run:${NC}"
        echo "./start-pipeline.sh"
        exit 0
    fi
fi

# Create Kind cluster
echo -e "\n${YELLOW}Creating Kind cluster with configuration...${NC}"
if kind create cluster --config kind-cluster-config.yaml; then
    echo -e "${GREEN}✅ Kind cluster created successfully!${NC}"
else
    echo -e "${RED}❌ Failed to create Kind cluster${NC}"
    exit 1
fi

# Setup kubeconfig
echo -e "\n${YELLOW}Setting up kubeconfig...${NC}"
kind get kubeconfig --name iot-pipeline > /tmp/iot-kubeconfig
export KUBECONFIG=/tmp/iot-kubeconfig

# Wait for cluster to be ready
echo -e "${YELLOW}Waiting for cluster to be ready...${NC}"
kubectl wait --for=condition=Ready nodes --all --timeout=60s

echo -e "\n${GREEN}🎉 Kind Cluster Created Successfully!${NC}"
echo "===================================="

echo -e "\n${BLUE}Cluster Information:${NC}"
kubectl get nodes
kubectl cluster-info

echo -e "\n${BLUE}Kubeconfig saved to: /tmp/iot-kubeconfig${NC}"
echo -e "${BLUE}To use this cluster in your terminal:${NC}"
echo "export KUBECONFIG=/tmp/iot-kubeconfig"

echo -e "\n${GREEN}Next Steps:${NC}"
echo "1. Run: ./start-pipeline.sh (to deploy the IoT pipeline)"
echo "2. Run: ./stop-pipeline.sh (to stop the pipeline)"
echo "3. Run: kind delete cluster --name iot-pipeline (to delete cluster)"

echo -e "\n${GREEN}Cluster is ready for IoT pipeline deployment!${NC} 🚀"