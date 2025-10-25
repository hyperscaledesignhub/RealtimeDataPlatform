#!/bin/bash

# ================================================================================
# Deploy IoT Producer to EKS with Configurable Topic Partitions
# ================================================================================
# This script deploys the IoT data producer pods to Kubernetes with a
# configurable number of topic partitions
# 
# Usage: ./deploy-with-partitions.sh [PARTITIONS] [REPLICAS]
# Example: ./deploy-with-partitions.sh 8 3
# 
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

# Parse command line arguments
PARTITIONS="${1:-4}"  # Default to 4 partitions if not specified
REPLICAS="${2:-3}"    # Default to 3 replicas if not specified
TOPIC_NAME="persistent://public/default/iot-sensor-data"

# Configuration
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-benchmark-high-infra}"
AWS_REGION="${AWS_REGION:-us-west-2}"
NAMESPACE="iot-pipeline"

# Validate inputs
if ! [[ "$PARTITIONS" =~ ^[0-9]+$ ]] || [ "$PARTITIONS" -lt 1 ]; then
    echo -e "${RED}ERROR: PARTITIONS must be a positive number${NC}"
    echo "Usage: $0 [PARTITIONS] [REPLICAS]"
    echo "Example: $0 8 3"
    exit 1
fi

if ! [[ "$REPLICAS" =~ ^[0-9]+$ ]] || [ "$REPLICAS" -lt 1 ] || [ "$REPLICAS" -gt 10 ]; then
    echo -e "${RED}ERROR: REPLICAS must be a number between 1 and 10${NC}"
    echo "Usage: $0 [PARTITIONS] [REPLICAS]"
    echo "Example: $0 8 3"
    exit 1
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IoT Producer Deployment with Partitions${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${BLUE}Partitions: $PARTITIONS${NC}"
echo -e "${BLUE}Replicas: $REPLICAS${NC}"
echo -e "${BLUE}Topic: $TOPIC_NAME${NC}"
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
if ! grep -q "dkr.ecr" producer-statefulset-perf.yaml; then
    echo -e "${RED}ERROR: producer-statefulset-perf.yaml doesn't have ECR image URL${NC}"
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
NODE_COUNT=$(kubectl get nodes -l workload=producer --no-headers 2>/dev/null | wc -l | tr -d ' ')

if [ "$NODE_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}⚠ WARNING: No nodes with workload=producer label found!${NC}"
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
    kubectl get nodes -l workload=producer
    echo ""
fi

# Stop existing deployment
echo -e "${YELLOW}==> Stopping existing producer deployment...${NC}"
kubectl scale statefulset iot-perf-producer -n "$NAMESPACE" --replicas=0 2>/dev/null || true
kubectl delete statefulset iot-perf-producer -n "$NAMESPACE" 2>/dev/null || true
echo -e "${GREEN}✓ Existing deployment stopped${NC}"
echo ""

# Create/update Pulsar topic with partitions
echo -e "${YELLOW}==> Creating Pulsar topic with $PARTITIONS partitions...${NC}"

# Initialize EXISTING_PARTITIONS to 0
EXISTING_PARTITIONS="0"

# Check if topic exists and has correct partitions
if kubectl exec -n pulsar pulsar-broker-0 -- bin/pulsar-admin topics list public/default 2>/dev/null | grep -q "iot-sensor-data"; then
    echo -e "${YELLOW}Topic exists, checking partition count...${NC}"
    EXISTING_PARTITIONS=$(kubectl exec -n pulsar pulsar-broker-0 -- bin/pulsar-admin topics get-partitioned-topic-metadata "$TOPIC_NAME" 2>/dev/null | grep -o '"partitions" : [0-9]*' | grep -o '[0-9]*' || echo "0")
    
    if [ "$EXISTING_PARTITIONS" = "$PARTITIONS" ]; then
        echo -e "${GREEN}✓ Topic already has $PARTITIONS partitions${NC}"
    else
        echo -e "${YELLOW}Topic has $EXISTING_PARTITIONS partitions, need $PARTITIONS. Deleting and recreating...${NC}"
        # Try to delete as partitioned topic first
        kubectl exec -n pulsar pulsar-broker-0 -- bin/pulsar-admin topics delete-partitioned-topic "$TOPIC_NAME" --force 2>/dev/null || \
        # If that fails, try regular delete
        kubectl exec -n pulsar pulsar-broker-0 -- bin/pulsar-admin topics delete "$TOPIC_NAME" --force 2>/dev/null || true
        sleep 3
    fi
fi

# Create partitioned topic (only if needed)
if [ "$EXISTING_PARTITIONS" != "$PARTITIONS" ]; then
    echo -e "${YELLOW}Creating partitioned topic with $PARTITIONS partitions...${NC}"
    if ! kubectl exec -n pulsar pulsar-broker-0 -- bin/pulsar-admin topics create-partitioned-topic "$TOPIC_NAME" --partitions "$PARTITIONS" 2>/dev/null; then
        echo -e "${RED}ERROR: Failed to create partitioned topic${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ Using existing topic with correct partition count${NC}"
fi

# Verify topic creation
echo -e "${YELLOW}Verifying topic creation...${NC}"
TOPIC_INFO=$(kubectl exec -n pulsar pulsar-broker-0 -- bin/pulsar-admin topics get-partitioned-topic-metadata "$TOPIC_NAME" 2>/dev/null)
if [ $? -ne 0 ]; then
    echo -e "${RED}ERROR: Failed to get topic metadata${NC}"
    exit 1
fi

echo "$TOPIC_INFO"

PARTITION_COUNT=$(echo "$TOPIC_INFO" | grep -o '"partitions" : [0-9]*' | grep -o '[0-9]*')
if [ "$PARTITION_COUNT" = "$PARTITIONS" ]; then
    echo -e "${GREEN}✓ Topic created with $PARTITIONS partitions${NC}"
else
    echo -e "${RED}ERROR: Topic creation failed or wrong partition count${NC}"
    echo -e "${RED}Expected: $PARTITIONS partitions, Got: $PARTITION_COUNT partitions${NC}"
    exit 1
fi
echo ""

# Set topic retention policy
echo -e "${YELLOW}==> Setting topic retention to 30 minutes...${NC}"
if ! kubectl exec -n pulsar pulsar-broker-0 -- bin/pulsar-admin topics set-retention "$TOPIC_NAME" --time 30m --size 10G; then
    echo -e "${RED}ERROR: Failed to set retention policy on topic${NC}"
    echo -e "${YELLOW}Continuing deployment...${NC}"
fi
echo -e "${GREEN}✓ Retention policy updated${NC}"
echo ""

# Update StatefulSet configuration
echo -e "${YELLOW}==> Updating StatefulSet configuration...${NC}"

# Create a temporary StatefulSet file with updated replicas
TEMP_STATEFULSET="/tmp/producer-statefulset-temp.yaml"
cp producer-statefulset-perf.yaml "$TEMP_STATEFULSET"

# Update replicas in the temporary file
sed -i.bak "s/replicas: 3/replicas: $REPLICAS/g" "$TEMP_STATEFULSET"

# Update NUM_REPLICAS environment variable to match actual replica count
sed -i.bak2 "s/value: \"3\"/value: \"$REPLICAS\"/g" "$TEMP_STATEFULSET"

echo -e "${GREEN}✓ StatefulSet configuration updated${NC}"
echo ""

# Deploy producer
echo -e "${YELLOW}==> Deploying IoT producer with $REPLICAS replicas...${NC}"
kubectl apply -f "$TEMP_STATEFULSET"

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
    -l app=iot-perf-producer \
    -n "$NAMESPACE" \
    --timeout=180s || {
    echo -e "${RED}Pods did not become ready in time${NC}"
    echo ""
    echo "Checking pod status:"
    kubectl get pods -n "$NAMESPACE"
    echo ""
    echo "Check logs with:"
    echo "  kubectl logs -n $NAMESPACE -l app=iot-perf-producer --tail=50"
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
kubectl get pods -n "$NAMESPACE" -l app=iot-perf-producer -o wide
echo ""

echo -e "${BLUE}StatefulSet:${NC}"
kubectl get statefulset iot-perf-producer -n "$NAMESPACE"
echo ""

echo -e "${BLUE}Topic Partitions:${NC}"
kubectl exec -n pulsar pulsar-broker-0 -- bin/pulsar-admin topics get-partitioned-topic-metadata "$TOPIC_NAME"
echo ""

# Show logs from one pod
echo -e "${BLUE}Recent logs (first pod):${NC}"
POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app=iot-perf-producer -o jsonpath='{.items[0].metadata.name}')
if [ -n "$POD_NAME" ]; then
    kubectl logs -n "$NAMESPACE" "$POD_NAME" --tail=20
fi
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Configuration Summary:"
echo "  - Topic: $TOPIC_NAME"
echo "  - Partitions: $PARTITIONS"
echo "  - Replicas: $REPLICAS"
echo "  - Total throughput: ~$((REPLICAS * 250000)) msg/sec"
echo ""
echo "Useful commands:"
echo ""
echo "  # Scale producer:"
echo "  kubectl scale statefulset iot-perf-producer -n $NAMESPACE --replicas=5"
echo ""
echo "  # View logs (all pods):"
echo "  kubectl logs -f -n $NAMESPACE -l app=iot-perf-producer"
echo ""
echo "  # View logs (specific pod):"
echo "  kubectl logs -f -n $NAMESPACE $POD_NAME"
echo ""
echo "  # Check Pulsar topic stats:"
echo "  kubectl exec -n pulsar pulsar-broker-0 -- bin/pulsar-admin topics stats $TOPIC_NAME"
echo ""
echo "  # Check topic partitions:"
echo "  kubectl exec -n pulsar pulsar-broker-0 -- bin/pulsar-admin topics get-partitioned-topic-metadata $TOPIC_NAME"
echo ""
echo "  # Delete deployment:"
echo "  kubectl delete statefulset iot-perf-producer -n $NAMESPACE"
echo ""

# Clean up temporary file
rm -f "$TEMP_STATEFULSET" "$TEMP_STATEFULSET.bak" "$TEMP_STATEFULSET.bak2"
