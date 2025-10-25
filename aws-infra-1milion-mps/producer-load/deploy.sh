#!/bin/bash

# ================================================================================
# Deploy IoT Producer to EKS
# ================================================================================
# This script deploys the IoT data producer pods to Kubernetes
# Prerequisites:
#   - EKS cluster is running
#   - kubectl is configured
#   - Docker image is built and pushed to ECR
# ================================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-benchmark-low-infra}"
AWS_REGION="${AWS_REGION:-us-west-2}"
NAMESPACE="iot-pipeline"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IoT Producer Deployment${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}==> Checking prerequisites...${NC}"

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}ERROR: kubectl not found${NC}"
    exit 1
fi

if ! command -v aws &> /dev/null; then
    echo -e "${RED}ERROR: aws CLI not found${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Prerequisites OK${NC}"
echo ""

# Configure kubectl
echo -e "${YELLOW}==> Configuring kubectl for EKS cluster: $EKS_CLUSTER_NAME${NC}"
aws eks update-kubeconfig --region "$AWS_REGION" --name "$EKS_CLUSTER_NAME"
echo -e "${GREEN}✓ kubectl configured${NC}"
echo ""

# Check if image is built
if ! grep -q "dkr.ecr" producer-deployment.yaml; then
    echo -e "${RED}ERROR: producer-deployment.yaml doesn't have ECR image URL${NC}"
    echo -e "${YELLOW}Please run ./build-and-push.sh first!${NC}"
    exit 1
fi

# Create/update namespace
echo -e "${YELLOW}==> Creating namespace: $NAMESPACE${NC}"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
echo -e "${GREEN}✓ Namespace ready${NC}"
echo ""

# Check if producer nodes exist
echo -e "${YELLOW}==> Checking for producer nodes...${NC}"
NODE_COUNT=$(kubectl get nodes -l workload=bench-producer --no-headers 2>/dev/null | wc -l | tr -d ' ')

if [ "$NODE_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}⚠ WARNING: No nodes with workload=bench-producer label found!${NC}"
    echo ""
    echo "Please ensure Terraform has created producer node group:"
    echo "  1. Check terraform.tfvars has: producer_desired_size = 3"
    echo "  2. Run: terraform apply"
    echo "  3. Wait for nodes to be ready"
    echo ""
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Deployment cancelled."
        exit 1
    fi
else
    echo -e "${GREEN}✓ Found $NODE_COUNT producer nodes${NC}"
    kubectl get nodes -l workload=bench-producer
    echo ""
fi

# Delete existing deployment (for clean updates)
echo -e "${YELLOW}==> Cleaning up existing deployment...${NC}"
kubectl delete deployment iot-producer -n "$NAMESPACE" --ignore-not-found=true
echo -e "${GREEN}✓ Cleanup complete${NC}"
echo ""

# Deploy producer
echo -e "${YELLOW}==> Deploying IoT producer...${NC}"
kubectl apply -f producer-deployment.yaml

if [ $? -ne 0 ]; then
    echo -e "${RED}ERROR: Deployment failed${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Producer deployed${NC}"
echo ""

# Wait for pods to be ready
echo -e "${YELLOW}==> Waiting for producer pods to be ready...${NC}"
echo "This may take 1-2 minutes..."
echo ""

kubectl wait --for=condition=ready pod \
    -l app=iot-producer \
    -n "$NAMESPACE" \
    --timeout=180s || {
    echo -e "${RED}Pods did not become ready in time${NC}"
    echo ""
    echo "Checking pod status:"
    kubectl get pods -n "$NAMESPACE"
    echo ""
    echo "Check logs with:"
    echo "  kubectl logs -n $NAMESPACE -l app=iot-producer --tail=50"
    exit 1
}

echo -e "${GREEN}✓ Pods are ready!${NC}"
echo ""

# Show deployment status
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Status${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo -e "${BLUE}Pods:${NC}"
kubectl get pods -n "$NAMESPACE" -l app=iot-producer -o wide
echo ""

echo -e "${BLUE}Deployment:${NC}"
kubectl get deployment iot-producer -n "$NAMESPACE"
echo ""

# Show logs from one pod
echo -e "${BLUE}Recent logs (first pod):${NC}"
POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app=iot-producer -o jsonpath='{.items[0].metadata.name}')
if [ -n "$POD_NAME" ]; then
    kubectl logs -n "$NAMESPACE" "$POD_NAME" --tail=20
fi
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Useful commands:"
echo ""
echo "  # Scale producer:"
echo "  kubectl scale deployment iot-producer -n $NAMESPACE --replicas=5"
echo ""
echo "  # View logs (all pods):"
echo "  kubectl logs -f -n $NAMESPACE -l app=iot-producer"
echo ""
echo "  # View logs (specific pod):"
echo "  kubectl logs -f -n $NAMESPACE $POD_NAME"
echo ""
echo "  # Check Pulsar topic stats:"
echo "  kubectl exec -n pulsar pulsar-broker-0 -- bin/pulsar-admin topics stats persistent://public/default/iot-sensor-data"
echo ""
echo "  # Delete deployment:"
echo "  kubectl delete deployment iot-producer -n $NAMESPACE"
echo ""

