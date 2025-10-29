#!/bin/bash
#
# Flink Job Deployment Script
# ============================
# Deploys the Flink job with ConfigMap and metrics monitoring
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLINK_NAMESPACE="flink-benchmark"
PULSAR_NAMESPACE="pulsar"

echo -e "${BLUE}======================================"
echo "Flink Job Deployment"
echo "======================================${NC}"
echo ""

# Check if namespace exists
echo -e "${YELLOW}Checking namespace: ${FLINK_NAMESPACE}...${NC}"
if ! kubectl get namespace ${FLINK_NAMESPACE} &> /dev/null; then
    echo -e "${YELLOW}Creating namespace ${FLINK_NAMESPACE}...${NC}"
    kubectl create namespace ${FLINK_NAMESPACE}
    echo -e "${GREEN}✓ Namespace created${NC}"
else
    echo -e "${GREEN}✓ Namespace exists${NC}"
fi
echo ""

# Step 1: Apply ConfigMap
echo -e "${YELLOW}[1/3] Applying Flink ConfigMap...${NC}"
if [ -f "$SCRIPT_DIR/flink-config-configmap.yaml" ]; then
    kubectl apply -f "$SCRIPT_DIR/flink-config-configmap.yaml"
    echo -e "${GREEN}✓ ConfigMap applied${NC}"
else
    echo -e "${YELLOW}⚠ ConfigMap file not found, skipping${NC}"
fi
echo ""

# Step 2: Apply Flink Job Deployment
echo -e "${YELLOW}[2/3] Deploying Flink Job...${NC}"
kubectl apply -f "$SCRIPT_DIR/flink-job-deployment.yaml"
echo -e "${GREEN}✓ Flink job deployed${NC}"
echo ""

# Step 3: Apply VMPodScrape for metrics
echo -e "${YELLOW}[3/3] Setting up metrics monitoring (VMPodScrape)...${NC}"
kubectl apply -f "$SCRIPT_DIR/flink-vmpodscrape.yaml"
echo -e "${GREEN}✓ VMPodScrape applied${NC}"
echo ""

# Wait for pods to start
echo -e "${YELLOW}Waiting for Flink pods to start (30 seconds)...${NC}"
sleep 30

# Check deployment status
echo -e "${BLUE}======================================"
echo "Deployment Status"
echo "======================================${NC}"
echo ""

echo -e "${CYAN}Flink Deployment:${NC}"
kubectl get flinkdeployment -n ${FLINK_NAMESPACE} 2>/dev/null || echo "No FlinkDeployment found"
echo ""

echo -e "${CYAN}Flink Pods:${NC}"
kubectl get pods -n ${FLINK_NAMESPACE}
echo ""

echo -e "${CYAN}VMPodScrape:${NC}"
kubectl get vmpodscrape -n ${PULSAR_NAMESPACE} flink-metrics 2>/dev/null || echo "VMPodScrape not found"
echo ""

echo -e "${BLUE}======================================"
echo -e "${GREEN}✅ Deployment Complete!${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

echo -e "${CYAN}Useful Commands:${NC}"
echo ""
echo "  # Check Flink job status:"
echo "  kubectl get flinkdeployment -n ${FLINK_NAMESPACE}"
echo ""
echo "  # View Flink logs:"
echo "  kubectl logs -n ${FLINK_NAMESPACE} -l app=iot-flink-job -f"
echo ""
echo "  # Access Flink UI:"
echo "  kubectl port-forward -n ${FLINK_NAMESPACE} svc/iot-flink-job-rest 8081:8081"
echo "  → http://localhost:8081"
echo ""
echo "  # Check metrics endpoint:"
echo "  kubectl port-forward -n ${FLINK_NAMESPACE} \$(kubectl get pods -n ${FLINK_NAMESPACE} -l component=jobmanager -o name | head -1) 9249:9249"
echo "  → http://localhost:9249/metrics"
echo ""
echo "  # Delete Flink job:"
echo "  kubectl delete flinkdeployment -n ${FLINK_NAMESPACE} iot-flink-job"
echo ""

