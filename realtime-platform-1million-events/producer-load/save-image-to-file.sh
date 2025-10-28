#!/bin/bash

# ================================================================================
# Save Docker Image as TAR file
# ================================================================================
# This saves your Docker image to a .tar file that can be:
# 1. Shared via file transfer (USB, network drive, etc.)
# 2. Loaded on another machine with: docker load -i <file>
# 
# WARNING: This image is 723MB! 
# NOT recommended for Git repositories - use GHCR instead!
# ================================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

LOCAL_IMAGE="bench-low-infra-iot-perf-producer:latest"
OUTPUT_FILE="iot-perf-producer-image.tar"
OUTPUT_PATH="./${OUTPUT_FILE}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Save Docker Image to TAR File${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if image exists
echo -e "${YELLOW}==> Checking Docker image...${NC}"
if ! docker image inspect "$LOCAL_IMAGE" &> /dev/null; then
    echo -e "${RED}ERROR: Image not found: $LOCAL_IMAGE${NC}"
    exit 1
fi

IMAGE_SIZE=$(docker image inspect "$LOCAL_IMAGE" --format='{{.Size}}' | awk '{print int($1/1024/1024)}')
echo -e "${GREEN}✓ Image found: ${IMAGE_SIZE}MB${NC}"
echo ""

# Check if output file already exists
if [ -f "$OUTPUT_PATH" ]; then
    echo -e "${YELLOW}⚠️  Output file already exists: $OUTPUT_PATH${NC}"
    read -p "Overwrite? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi
    rm "$OUTPUT_PATH"
fi

# Save image to tar
echo -e "${YELLOW}==> Saving Docker image to TAR file...${NC}"
echo "This will take 2-5 minutes for ${IMAGE_SIZE}MB..."
echo ""

docker save "$LOCAL_IMAGE" -o "$OUTPUT_PATH"

if [ $? -ne 0 ]; then
    echo -e "${RED}ERROR: Failed to save image${NC}"
    exit 1
fi

TAR_SIZE=$(ls -lh "$OUTPUT_PATH" | awk '{print $5}')
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Image Saved Successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "📦 File: $OUTPUT_PATH"
echo "📊 Size: $TAR_SIZE"
echo ""
echo "🚀 To load on another machine:"
echo "   docker load -i $OUTPUT_FILE"
echo ""
echo -e "${RED}⚠️  WARNING: NOT RECOMMENDED FOR GIT!${NC}"
echo "   This file is too large (${TAR_SIZE}) for Git repositories!"
echo ""
echo "✅ Better alternatives:"
echo "   1. Push to GitHub Container Registry:"
echo "      ./push-to-github.sh"
echo ""
echo "   2. Push to Docker Hub:"
echo "      ./push-to-dockerhub.sh"
echo ""
echo "   3. Use Git LFS (Large File Storage) if you must use Git:"
echo "      git lfs track '*.tar'"
echo "      git add .gitattributes $OUTPUT_FILE"
echo ""

