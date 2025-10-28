#!/bin/bash

# ================================================================================
# Push Pre-Built IoT Performance Producer Image to GitHub Container Registry
# ================================================================================
# This script tags and pushes the existing local image to ghcr.io
# No rebuild needed - uses the image you already have!
# Repository: https://github.com/hyperscaledesignhub/docker-images
# ================================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
GITHUB_ORG="hyperscaledesignhub"
IMAGE_NAME="iot-perf-producer"
IMAGE_TAG="${IMAGE_TAG:-latest}"
LOCAL_IMAGE="bench-low-infra-iot-perf-producer:latest"
REMOTE_IMAGE="ghcr.io/${GITHUB_ORG}/${IMAGE_NAME}:${IMAGE_TAG}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Push to GitHub Container Registry${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "GitHub Org:   $GITHUB_ORG"
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
IMAGE_DATE=$(docker image inspect "$LOCAL_IMAGE" --format='{{.Created}}' | cut -d'T' -f1)
echo -e "${GREEN}✓ Local image found${NC}"
echo "  Size: ${IMAGE_SIZE}MB"
echo "  Created: ${IMAGE_DATE}"
echo ""

# Check GitHub authentication
echo -e "${YELLOW}==> Checking GitHub Container Registry authentication...${NC}"
echo ""
echo "To authenticate, you need a GitHub Personal Access Token (PAT) with 'write:packages' scope"
echo ""
echo "Create one at: https://github.com/settings/tokens/new"
echo "Required scopes: write:packages, read:packages, delete:packages (optional)"
echo ""

if ! docker info 2>/dev/null | grep -q "ghcr.io"; then
    echo -e "${YELLOW}Please enter your GitHub username and token:${NC}"
    echo ""
    read -p "GitHub Username: " GITHUB_USERNAME
    read -sp "GitHub Token (PAT): " GITHUB_TOKEN
    echo ""
    echo ""
    
    echo "$GITHUB_TOKEN" | docker login ghcr.io -u "$GITHUB_USERNAME" --password-stdin
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}ERROR: GitHub authentication failed${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ Already authenticated with GitHub Container Registry${NC}"
fi
echo ""

# Tag the image (remove any AWS account IDs from the tag)
echo -e "${YELLOW}==> Tagging image for GitHub Container Registry...${NC}"
docker tag "$LOCAL_IMAGE" "$REMOTE_IMAGE"
echo -e "${GREEN}✓ Image tagged as: $REMOTE_IMAGE${NC}"
echo ""

# Push to GitHub Container Registry
echo -e "${YELLOW}==> Pushing to GitHub Container Registry...${NC}"
echo "Uploading ${IMAGE_SIZE}MB (this may take 3-5 minutes)..."
echo ""

docker push "$REMOTE_IMAGE"

if [ $? -ne 0 ]; then
    echo -e "${RED}ERROR: Docker push failed${NC}"
    echo ""
    echo "Common issues:"
    echo "  1. Token missing 'write:packages' scope"
    echo "  2. Not a member of hyperscaledesignhub organization"
    echo "  3. Repository doesn't exist in the organization"
    exit 1
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Push Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "📦 Image pushed successfully!"
echo ""
echo "🔗 GitHub Container Registry:"
echo "   https://github.com/orgs/hyperscaledesignhub/packages/container/package/${IMAGE_NAME}"
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
echo "🚀 Anyone with access can pull this image with:"
echo "   docker pull ${REMOTE_IMAGE}"
echo ""
echo "Note: By default, packages are private. To make it public:"
echo "   1. Go to: https://github.com/orgs/hyperscaledesignhub/packages"
echo "   2. Click on ${IMAGE_NAME}"
echo "   3. Package settings > Change visibility > Public"
echo ""

