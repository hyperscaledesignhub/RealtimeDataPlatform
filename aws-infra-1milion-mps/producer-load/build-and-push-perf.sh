#!/bin/bash

# ================================================================================
# Build and Push IoT Performance Producer (pulsar-sensor-perf) to ECR
# ================================================================================
# This script:
#   1. Copies the pulsar-sensor-perf binary and target from aws-deploy/scripts
#   2. Builds the Docker image for x86_64 (linux/amd64)
#   3. Creates ECR repository if it doesn't exist
#   4. Pushes the image to ECR
#   5. Updates producer-deployment-perf.yaml with the correct image URL
# ================================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
AWS_REGION="${AWS_REGION:-us-west-2}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO_NAME="bench-low-infra-iot-perf-producer"
IMAGE_TAG="${IMAGE_TAG:-latest}"
FULL_IMAGE_NAME="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}:${IMAGE_TAG}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IoT Performance Producer - Build and Push${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "AWS Account: $AWS_ACCOUNT_ID"
echo "AWS Region: $AWS_REGION"
echo "ECR Repository: $ECR_REPO_NAME"
echo "Image Tag: $IMAGE_TAG"
echo "Full Image: $FULL_IMAGE_NAME"
echo ""

# Copy pulsar-sensor-perf binary and target from aws-deploy/scripts
echo -e "${YELLOW}==> Copying pulsar-sensor-perf binary and target...${NC}"

SOURCE_DIR="../../../aws-deploy/scripts"
if [ ! -f "$SOURCE_DIR/pulsar-sensor-perf" ]; then
    echo -e "${RED}ERROR: pulsar-sensor-perf not found at $SOURCE_DIR${NC}"
    exit 1
fi

if [ ! -d "$SOURCE_DIR/target" ]; then
    echo -e "${RED}ERROR: target directory not found at $SOURCE_DIR${NC}"
    exit 1
fi

# Copy files
cp "$SOURCE_DIR/pulsar-sensor-perf" .
cp -r "$SOURCE_DIR/target" .

echo -e "${GREEN}✓ Files copied${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}==> Checking prerequisites...${NC}"

if ! command -v docker &> /dev/null; then
    echo -e "${RED}ERROR: docker not found. Please install Docker.${NC}"
    exit 1
fi

if ! command -v aws &> /dev/null; then
    echo -e "${RED}ERROR: aws CLI not found. Please install AWS CLI.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Prerequisites OK${NC}"
echo ""

# Authenticate Docker to ECR
echo -e "${YELLOW}==> Authenticating Docker to ECR...${NC}"
aws ecr get-login-password --region "$AWS_REGION" | \
    docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
echo -e "${GREEN}✓ Docker authenticated to ECR${NC}"
echo ""

# Create ECR repository if it doesn't exist
echo -e "${YELLOW}==> Checking ECR repository...${NC}"
if ! aws ecr describe-repositories --region "$AWS_REGION" --repository-names "$ECR_REPO_NAME" &> /dev/null; then
    echo "Repository doesn't exist. Creating..."
    aws ecr create-repository \
        --region "$AWS_REGION" \
        --repository-name "$ECR_REPO_NAME" \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256 \
        --tags Key=Project,Value=flink-benchmark Key=Component,Value=perf-producer
    echo -e "${GREEN}✓ ECR repository created${NC}"
else
    echo -e "${GREEN}✓ ECR repository exists${NC}"
fi
echo ""

# Build Docker image
echo -e "${YELLOW}==> Building Docker image for linux/amd64 (x86_64)...${NC}"
echo "This may take a few minutes..."
echo ""

docker build \
    --platform linux/amd64 \
    --file Dockerfile.perf \
    --tag "$FULL_IMAGE_NAME" \
    --tag "${ECR_REPO_NAME}:${IMAGE_TAG}" \
    --progress=plain \
    .

if [ $? -ne 0 ]; then
    echo -e "${RED}ERROR: Docker build failed${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✓ Docker image built successfully${NC}"
echo ""

# Push to ECR
echo -e "${YELLOW}==> Pushing image to ECR...${NC}"
docker push "$FULL_IMAGE_NAME"

if [ $? -ne 0 ]; then
    echo -e "${RED}ERROR: Docker push failed${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✓ Image pushed to ECR successfully${NC}"
echo ""

# Update producer-deployment-perf.yaml
echo -e "${YELLOW}==> Updating producer-deployment-perf.yaml...${NC}"

if [ -f "producer-deployment-perf.yaml" ]; then
    # Use sed to update the image line
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s|image:.*|image: ${FULL_IMAGE_NAME}|g" producer-deployment-perf.yaml
    else
        # Linux
        sed -i "s|image:.*|image: ${FULL_IMAGE_NAME}|g" producer-deployment-perf.yaml
    fi
    echo -e "${GREEN}✓ producer-deployment-perf.yaml updated${NC}"
    echo ""
    echo "Updated image line:"
    grep "image:" producer-deployment-perf.yaml | head -1
else
    echo -e "${YELLOW}⚠ producer-deployment-perf.yaml not found${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Build and Push Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Image: $FULL_IMAGE_NAME"
echo ""
echo "Next steps:"
echo "  1. Deploy to Kubernetes:"
echo "     kubectl apply -f producer-deployment-perf.yaml"
echo ""
echo "  2. Check pod status:"
echo "     kubectl get pods -n iot-pipeline"
echo ""
echo "  3. View producer logs:"
echo "     kubectl logs -f deployment/iot-perf-producer -n iot-pipeline"
echo ""

