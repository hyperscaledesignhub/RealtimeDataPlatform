#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse command line arguments
DESIRED_REPLICAS="${1}"
NAMESPACE="iot-pipeline"
STATEFULSET_NAME="iot-perf-producer"

# Validate inputs
if ! [[ "$DESIRED_REPLICAS" =~ ^[0-9]+$ ]] || [ "$DESIRED_REPLICAS" -lt 1 ]; then
    echo -e "${RED}ERROR: DESIRED_REPLICAS must be a positive number${NC}"
    echo "Usage: $0 [DESIRED_REPLICAS]"
    echo "Example: $0 4"
    exit 1
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Gradual Scaling of IoT Producer${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${BLUE}Target Replicas: $DESIRED_REPLICAS${NC}"
echo ""

# Get current number of replicas
CURRENT_REPLICAS=$(kubectl get statefulset "$STATEFULSET_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')

echo -e "${YELLOW}==> Current replicas: $CURRENT_REPLICAS${NC}"
echo ""

# Update NUM_REPLICAS environment variable to match target replica count
echo -e "${YELLOW}==> Updating NUM_REPLICAS environment variable to $DESIRED_REPLICAS...${NC}"
kubectl set env statefulset/"$STATEFULSET_NAME" -n "$NAMESPACE" NUM_REPLICAS="$DESIRED_REPLICAS"
if [ $? -ne 0 ]; then
    echo -e "${RED}ERROR: Failed to update NUM_REPLICAS environment variable${NC}"
    exit 1
fi
echo -e "${GREEN}✓ NUM_REPLICAS updated to $DESIRED_REPLICAS${NC}"
echo ""

if [ "$DESIRED_REPLICAS" -le "$CURRENT_REPLICAS" ]; then
    echo -e "${YELLOW}Desired replica count is not greater than current. Scaling down at once.${NC}"
    kubectl scale statefulset "$STATEFULSET_NAME" -n "$NAMESPACE" --replicas="$DESIRED_REPLICAS"
    echo -e "${GREEN}✓ Scaled down to $DESIRED_REPLICAS replicas${NC}"
    exit 0
fi

for i in $(seq $((CURRENT_REPLICAS + 1)) "$DESIRED_REPLICAS"); do
    echo -e "${GREEN}========================================${NC}"
    echo -e "${BLUE}Scaling to $i replicas...${NC}"
    echo -e "${GREEN}========================================${NC}"

    echo -e "${YELLOW}==> Scaling StatefulSet to $i replicas...${NC}"
    kubectl scale statefulset "$STATEFULSET_NAME" -n "$NAMESPACE" --replicas="$i"
    if [ $? -ne 0 ]; then
        echo -e "${RED}ERROR: Failed to scale StatefulSet${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ StatefulSet scaled${NC}"
    echo ""

    POD_NAME="$STATEFULSET_NAME-$((i - 1))"
        echo -e "${YELLOW}==> Waiting for pod $POD_NAME to be created...${NC}"
    
    # Wait for pod to be created (up to 60 seconds)
    WAIT_COUNT=0
    while [ $WAIT_COUNT -lt 60 ]; do
        if kubectl get pod "$POD_NAME" -n "$NAMESPACE" &>/dev/null; then
            echo -e "${GREEN}✓ Pod $POD_NAME created${NC}"
            break
        fi
        sleep 1
        WAIT_COUNT=$((WAIT_COUNT + 1))
    done
    
    if [ $WAIT_COUNT -eq 60 ]; then
        echo -e "${RED}ERROR: Pod $POD_NAME was not created in time${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}==> Waiting for pod $POD_NAME to be ready...${NC}"
    kubectl wait --for=condition=ready pod "$POD_NAME" -n "$NAMESPACE" --timeout=180s
    if [ $? -ne 0 ]; then
        echo -e "${RED}ERROR: Pod $POD_NAME did not become ready in time${NC}"
        echo -e "${YELLOW}Checking pod status:${NC}"
        kubectl describe pod "$POD_NAME" -n "$NAMESPACE" | tail -20
        exit 1
    fi
    echo -e "${GREEN}✓ Pod $POD_NAME is ready${NC}"
    echo ""

    if [ "$i" -lt "$DESIRED_REPLICAS" ]; then
        echo -e "${BLUE}==> Waiting for 1 minute before scaling to the next replica...${NC}"
        sleep 60
    fi
done

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Gradual scaling complete!${NC}"
echo -e "${GREEN}========================================${NC}"