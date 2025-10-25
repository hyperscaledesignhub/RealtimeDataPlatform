#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Flink Operator version
FLINK_OPERATOR_VERSION=${FLINK_OPERATOR_VERSION:-1.7.0}

echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}   Installing Official Flink Kubernetes Operator    ${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed${NC}"
    exit 1
fi

# Check if connected to a cluster
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Error: Not connected to a Kubernetes cluster${NC}"
    echo "Run: aws eks update-kubeconfig --region <region> --name <cluster-name>"
    exit 1
fi

echo -e "${BLUE}Using Flink Operator version: ${FLINK_OPERATOR_VERSION}${NC}"
echo

# Step 1: Install Flink Operator CRDs and Controller
echo -e "${YELLOW}Step 1: Installing Flink Operator CRDs and Controller...${NC}"
kubectl create -f https://github.com/apache/flink-kubernetes-operator/releases/download/release-${FLINK_OPERATOR_VERSION}/flink-kubernetes-operator-${FLINK_OPERATOR_VERSION}.yml

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to install Flink Operator${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Flink Operator installed${NC}"
echo

# Step 2: Wait for CRDs to be established
echo -e "${YELLOW}Step 2: Waiting for CRDs to be established...${NC}"
kubectl wait --for condition=established --timeout=60s crd/flinkdeployments.flink.apache.org
kubectl wait --for condition=established --timeout=60s crd/flinksessionjobs.flink.apache.org

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Flink CRDs established${NC}"
else
    echo -e "${RED}Failed to establish Flink CRDs${NC}"
    exit 1
fi
echo

# Step 3: Wait for operator pod to be ready
echo -e "${YELLOW}Step 3: Waiting for Flink Operator pod to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=flink-kubernetes-operator -n flink-operator-system --timeout=300s

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Flink Operator pod is ready${NC}"
else
    echo -e "${YELLOW}Warning: Operator pod may not be ready yet${NC}"
fi
echo

# Step 4: Verify installation
echo -e "${YELLOW}Step 4: Verifying installation...${NC}"

echo -e "${BLUE}CRDs installed:${NC}"
kubectl get crd | grep flink

echo
echo -e "${BLUE}Operator pods:${NC}"
kubectl get pods -n flink-operator-system

echo
echo -e "${BLUE}Operator logs (last 10 lines):${NC}"
kubectl logs -n flink-operator-system -l app.kubernetes.io/name=flink-kubernetes-operator --tail=10

echo
echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}   Flink Operator Installation Complete!            ${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo

echo -e "${BLUE}Next steps:${NC}"
echo "1. Create namespace for Flink:"
echo "   kubectl create namespace flink-benchmark"
echo
echo "2. Create service account:"
echo "   kubectl apply -f flink-serviceaccount.yaml"
echo
echo "3. Deploy Flink cluster:"
echo "   kubectl apply -f flink-deployment.yaml"
echo
echo "4. Check deployment status:"
echo "   kubectl get flinkdeployment -n flink-benchmark"
echo
echo "5. Port forward to access Flink UI:"
echo "   kubectl port-forward -n flink-benchmark svc/flink-benchmark-cluster-rest 8081:8081"
echo

echo -e "${YELLOW}Useful commands:${NC}"
echo "# View operator logs:"
echo "kubectl logs -n flink-operator-system -l app.kubernetes.io/name=flink-kubernetes-operator -f"
echo
echo "# Check CRDs:"
echo "kubectl get crd | grep flink"
echo
echo "# Uninstall operator:"
echo "kubectl delete -f https://github.com/apache/flink-kubernetes-operator/releases/download/release-${FLINK_OPERATOR_VERSION}/flink-kubernetes-operator-${FLINK_OPERATOR_VERSION}.yml"

