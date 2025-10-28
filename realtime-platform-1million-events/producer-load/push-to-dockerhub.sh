#!/bin/bash

# ================================================================================
# Push Pre-Built IoT Performance Producer Image to Docker Hub
# ================================================================================
# This script tags and pushes the existing local image to Docker Hub
# No rebuild needed - uses the image you already have!
# ================================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration - CHANGE THESE!
DOCKERHUB_USERNAME="${DOCKERHUB_USERNAME:-vijayabhaskarv}"  # Your Docker Hub username
IMAGE_NAME="iot-perf-producer"
IMAGE_TAG="${IMAGE_TAG:-latest}"
LOCAL_IMAGE="bench-low-infra-iot-perf-producer:latest"
REMOTE_IMAGE="${DOCKERHUB_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Push IoT Performance Producer to Docker Hub${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Local Image:  $LOCAL_IMAGE"
echo "Remote Image: $REMOTE_IMAGE"
echo ""

# Check if local image exists
echo -e "${YELLOW}==> Checking local image...${NC}"
if ! docker image inspect "$LOCAL_IMAGE" &> /dev/null; then
    echo -e "${RED}ERROR: Local image not found: $LOCAL_IMAGE${NC}"
    echo "Available images:"
    docker images | grep "perf-producer"
    exit 1
fi

IMAGE_SIZE=$(docker image inspect "$LOCAL_IMAGE" --format='{{.Size}}' | awk '{print int($1/1024/1024)}')
echo -e "${GREEN}✓ Local image found (${IMAGE_SIZE}MB)${NC}"
echo ""

# Check Docker Hub login
echo -e "${YELLOW}==> Checking Docker Hub authentication...${NC}"
if ! docker info 2>/dev/null | grep -q "Username: $DOCKERHUB_USERNAME"; then
    echo "Not logged in to Docker Hub. Logging in..."
    echo ""
    echo -e "${YELLOW}Please enter your Docker Hub credentials:${NC}"
    docker login
else
    echo -e "${GREEN}✓ Already logged in to Docker Hub${NC}"
fi
echo ""

# Tag the image
echo -e "${YELLOW}==> Tagging image...${NC}"
docker tag "$LOCAL_IMAGE" "$REMOTE_IMAGE"
echo -e "${GREEN}✓ Image tagged as: $REMOTE_IMAGE${NC}"
echo ""

# Push to Docker Hub
echo -e "${YELLOW}==> Pushing to Docker Hub (this may take a few minutes)...${NC}"
echo "Uploading ${IMAGE_SIZE}MB..."
echo ""

docker push "$REMOTE_IMAGE"

if [ $? -ne 0 ]; then
    echo -e "${RED}ERROR: Docker push failed${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Push Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "📦 Image pushed successfully!"
echo ""
echo "🔗 Docker Hub URL:"
echo "   https://hub.docker.com/r/${DOCKERHUB_USERNAME}/${IMAGE_NAME}"
echo ""
echo "📋 To use this image in Kubernetes:"
echo ""
echo "   Update your producer-deployment-perf.yaml:"
echo "   ---"
echo "   spec:"
echo "     containers:"
echo "     - name: iot-perf-producer"
echo "       image: ${REMOTE_IMAGE}"
echo ""
echo "🚀 Anyone can now pull this image with:"
echo "   docker pull ${REMOTE_IMAGE}"
echo ""
echo "   Or in Kubernetes, it will automatically pull from Docker Hub!"
echo ""

