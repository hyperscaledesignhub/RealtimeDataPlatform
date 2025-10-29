#!/bin/bash

# ================================================================================
# Deploy IoT Producer to EKS with Configurable Topic Partitions
# ================================================================================
# This script deploys the IoT data producer pods to Kubernetes with a
# configurable number of topic partitions and replica scaling
# 
# Usage: ./deploy-with-partitions.sh [PARTITIONS] [MIN_REPLICAS] [MAX_REPLICAS]
# Example: ./deploy-with-partitions.sh 64 1 10
# 
# Arguments:
#   PARTITIONS     - Number of topic partitions (default: 4)
#   MIN_REPLICAS   - Initial number of producer replicas (default: 1)
#   MAX_REPLICAS   - Maximum replicas for scaling (default: MIN_REPLICAS)
# 
# Behavior:
#   - When Flink is NOT running: Creates topic with PARTITIONS, no producer deployment
#   - When Flink IS running: Skips topic creation, deploys MIN_REPLICAS producer pods
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
REPLICAS="${2:-1}"    # Default to 1 replica if not specified
MAX_REPLICAS="${3:-$REPLICAS}" # Default to REPLICAS if not specified
TOPIC_NAME="persistent://public/default/iot-sensor-data"

# Configuration
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-benchmark-high-infra}"
AWS_REGION="${AWS_REGION:-us-west-2}"
NAMESPACE="iot-pipeline"

# Validate inputs
if ! [[ "$PARTITIONS" =~ ^[0-9]+$ ]] || [ "$PARTITIONS" -lt 1 ]; then
    echo -e "${RED}ERROR: PARTITIONS must be a positive number${NC}"
    echo "Usage: $0 [PARTITIONS] [MIN_REPLICAS] [MAX_REPLICAS]"
    echo "Example: $0 64 1 10"
    exit 1
fi

if ! [[ "$REPLICAS" =~ ^[0-9]+$ ]] || [ "$REPLICAS" -lt 1 ] || [ "$REPLICAS" -gt 10 ]; then
    echo -e "${RED}ERROR: MIN_REPLICAS must be a number between 1 and 10${NC}"
    echo "Usage: $0 [PARTITIONS] [MIN_REPLICAS] [MAX_REPLICAS]"
    echo "Example: $0 64 1 10"
    exit 1
fi

if ! [[ "$MAX_REPLICAS" =~ ^[0-9]+$ ]] || [ "$MAX_REPLICAS" -lt "$REPLICAS" ]; then
    echo -e "${RED}ERROR: MAX_REPLICAS must be >= MIN_REPLICAS${NC}"
    echo "Usage: $0 [PARTITIONS] [MIN_REPLICAS] [MAX_REPLICAS]"
    echo "Example: $0 64 1 10"
    exit 1
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IoT Producer Deployment with Partitions${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${BLUE}Partitions: $PARTITIONS${NC}"
echo -e "${BLUE}Initial Replicas: $REPLICAS${NC}"
echo -e "${BLUE}Max Replicas: $MAX_REPLICAS${NC}"
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

# Check if image is built (accept both ECR and GHCR)
if ! grep -q -E "(dkr\.ecr|ghcr\.io)" producer-statefulset-perf.yaml; then
    echo -e "${RED}ERROR: producer-statefulset-perf.yaml doesn't have a valid container image URL${NC}"
    echo -e "${YELLOW}Please ensure the image is set to either ECR or GHCR${NC}"
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

# Check if Flink job is running (in flink-benchmark namespace)
echo -e "${YELLOW}==> Checking Flink job status...${NC}"
FLINK_RUNNING=false
FLINK_NAMESPACE="flink-benchmark"

# Check if Flink deployment exists
if kubectl get deployment -n "$FLINK_NAMESPACE" &> /dev/null 2>&1; then
    # Check for running Flink pods
    FLINK_PODS=$(kubectl get pods -n "$FLINK_NAMESPACE" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "$FLINK_PODS" -gt 0 ]; then
        FLINK_RUNNING=true
        echo -e "${GREEN}✓ Flink job is running in namespace '$FLINK_NAMESPACE' ($FLINK_PODS pods)${NC}"
        echo "   Pods:"
        kubectl get pods -n "$FLINK_NAMESPACE" --no-headers | head -5
    else
        echo -e "${YELLOW}⚠ Flink namespace exists but no Running pods found${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Flink namespace '$FLINK_NAMESPACE' not found${NC}"
fi
echo ""

# If Flink is NOT running, create topic with PARTITIONS and exit (no producer deployment)
if [ "$FLINK_RUNNING" = false ]; then
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}⚠️  FLINK JOB IS NOT RUNNING!${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo "The Flink consumer job must be running before starting producers."
    echo "Otherwise, messages will accumulate without being consumed."
    echo ""
    echo -e "${YELLOW}==> Creating Pulsar topic with $PARTITIONS partitions (preparation)...${NC}"
    echo -e "${YELLOW}Note: Topic will be created with PARTITIONS ($PARTITIONS) since Flink is not running${NC}"
    echo ""
    
    # Create topic but don't deploy producers
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
            kubectl exec -n pulsar pulsar-broker-0 -- bin/pulsar-admin topics delete-partitioned-topic "$TOPIC_NAME" --force 2>/dev/null || \
            kubectl exec -n pulsar pulsar-broker-0 -- bin/pulsar-admin topics delete "$TOPIC_NAME" --force 2>/dev/null || true
            sleep 3
        fi
    fi
    
    # Create partitioned topic with PARTITIONS (only if needed)
    if [ "$EXISTING_PARTITIONS" != "$PARTITIONS" ]; then
        echo -e "${YELLOW}Creating partitioned topic with $PARTITIONS partitions...${NC}"
        CREATE_OUTPUT=$(kubectl exec -n pulsar pulsar-broker-0 -- bin/pulsar-admin topics create-partitioned-topic "$TOPIC_NAME" --partitions "$PARTITIONS" 2>&1)
        CREATE_EXIT=$?
        
        if [ $CREATE_EXIT -eq 0 ]; then
            echo -e "${GREEN}✓ Topic created with $PARTITIONS partitions${NC}"
        elif echo "$CREATE_OUTPUT" | grep -q "already exists"; then
            echo -e "${GREEN}✓ Topic already exists with $PARTITIONS partitions${NC}"
        else
            echo -e "${RED}ERROR: Failed to create partitioned topic${NC}"
            echo "$CREATE_OUTPUT"
            exit 1
        fi
    fi
    
    # Set retention
    echo -e "${YELLOW}Setting topic retention to 30 minutes...${NC}"
    kubectl exec -n pulsar pulsar-broker-0 -- bin/pulsar-admin topics set-retention "$TOPIC_NAME" --time 30m --size 10G 2>/dev/null || true
    echo -e "${GREEN}✓ Retention policy updated${NC}"
    
    echo ""
    echo -e "${GREEN}✓ Topic preparation complete!${NC}"
    echo ""
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}NEXT STEPS:${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo ""
    echo "Topic created with PARTITIONS ($PARTITIONS)."
    echo "Producers will NOT be deployed until Flink is running."
    echo ""
    echo "1. Start the Flink consumer job:"
    echo "   cd ../flink-load"
    echo "   kubectl apply -f flink-job-deployment.yaml"
    echo ""
    echo "2. Wait for Flink job to be running:"
    echo "   kubectl get pods -n flink-benchmark"
    echo ""
    echo "3. Then run this script again to deploy producers:"
    echo "   ./deploy-with-partitions.sh $PARTITIONS $REPLICAS $MAX_REPLICAS"
    echo ""
    exit 0
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Flink is running - proceeding with deployment${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Stop existing deployment
echo -e "${YELLOW}==> Stopping existing producer deployment...${NC}"
kubectl scale statefulset iot-perf-producer -n "$NAMESPACE" --replicas=0 2>/dev/null || true
kubectl delete statefulset iot-perf-producer -n "$NAMESPACE" 2>/dev/null || true
echo -e "${GREEN}✓ Existing deployment stopped${NC}"
echo ""

# When Flink is running, skip topic creation and just verify it exists
echo -e "${YELLOW}==> Verifying Pulsar topic exists...${NC}"
echo -e "${YELLOW}Note: Skipping topic creation since Flink is running. Using existing topic.${NC}"

# Check if topic exists by checking partitioned topic metadata (works for both partitioned and non-partitioned)
EXISTING_PARTITIONS=$(kubectl exec -n pulsar pulsar-broker-0 -- bin/pulsar-admin topics get-partitioned-topic-metadata "$TOPIC_NAME" 2>/dev/null | grep -o '"partitions" : [0-9]*' | grep -o '[0-9]*' || echo "0")

if [ "$EXISTING_PARTITIONS" -gt 0 ] || kubectl exec -n pulsar pulsar-broker-0 -- bin/pulsar-admin topics list public/default 2>/dev/null | grep -q "^${TOPIC_NAME}$"; then
    if [ "$EXISTING_PARTITIONS" -gt 0 ]; then
        echo -e "${GREEN}✓ Partitioned topic exists with $EXISTING_PARTITIONS partitions${NC}"
    else
        echo -e "${GREEN}✓ Non-partitioned topic exists${NC}"
        EXISTING_PARTITIONS=1
    fi
    
    # Set retention policy if topic exists
    echo -e "${YELLOW}Setting topic retention to 30 minutes...${NC}"
    kubectl exec -n pulsar pulsar-broker-0 -- bin/pulsar-admin topics set-retention "$TOPIC_NAME" --time 30m --size 10G 2>/dev/null || true
    echo -e "${GREEN}✓ Retention policy updated${NC}"
else
    echo -e "${RED}ERROR: Topic does not exist!${NC}"
    echo ""
    echo "Please run this script first when Flink is NOT running to create the topic:"
    echo "  ./deploy-with-partitions.sh $PARTITIONS $REPLICAS $MAX_REPLICAS"
    echo ""
    exit 1
fi
echo ""

# Update StatefulSet configuration
echo -e "${YELLOW}==> Updating StatefulSet configuration...${NC}"

# Create a temporary StatefulSet file with updated replicas
TEMP_STATEFULSET="/tmp/producer-statefulset-temp.yaml"
cp producer-statefulset-perf.yaml "$TEMP_STATEFULSET"

# Update replicas in the temporary file (start with MIN_REPLICAS)
sed -i.bak "s/replicas: [0-9]*/replicas: $REPLICAS/g" "$TEMP_STATEFULSET"

# Update NUM_REPLICAS environment variable for device distribution (use MAX_REPLICAS for total device calculation)
if grep -q "NUM_REPLICAS" "$TEMP_STATEFULSET"; then
    sed -i.bak2 "s/value: \"[0-9]*\" # NUM_REPLICAS/value: \"$MAX_REPLICAS\" # NUM_REPLICAS/g" "$TEMP_STATEFULSET"
fi

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
echo "  - Topic Partitions: $EXISTING_PARTITIONS (existing topic, not modified)"
echo "  - Producer Replicas: $REPLICAS (MIN_REPLICAS)"
echo "  - Max Replicas: $MAX_REPLICAS"
echo "  - Current throughput: ~$((REPLICAS * 250000)) msg/sec"
echo "  - Max throughput: ~$((MAX_REPLICAS * 250000)) msg/sec"
echo ""
echo "Useful commands:"
echo ""
echo "  # Scale producer (up to $MAX_REPLICAS):"
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
