#!/bin/bash
#
# Build and Push Flink Consumer Docker Image to AWS ECR
# ======================================================
# This script builds the Flink consumer JAR and pushes it to ECR
# Builds for x86_64 architecture (even on ARM Macs)
#
# PREREQUISITES:
#   - Docker installed and running
#   - AWS CLI configured
#   - ECR repository exists (created by Terraform)
#
# USAGE:
#   cd /Users/vijayabhaskarv/IOT/datapipeline-0/Flink-Benchmark/low_infra_flink/flink-load
#   chmod +x build-and-push.sh
#   ./build-and-push.sh
#
# ======================================================

set -e

echo "======================================"
echo "Flink Consumer - Build and Push to ECR"
echo "======================================"
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
AWS_REGION=${AWS_REGION:-us-west-2}
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPOSITORY="bench-low-infra-flink-job"
IMAGE_TAG=${IMAGE_TAG:-latest}

echo -e "${YELLOW}Configuration:${NC}"
echo "  AWS Region: ${AWS_REGION}"
echo "  AWS Account: ${AWS_ACCOUNT_ID}"
echo "  ECR Repository: ${ECR_REPOSITORY}"
echo "  Image Tag: ${IMAGE_TAG}"
echo "  Platform: linux/amd64 (x86_64)"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker is not installed or not running${NC}"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo -e "${RED}❌ Docker daemon is not running${NC}"
    exit 1
fi

if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ AWS CLI is not installed${NC}"
    exit 1
fi

echo -e "${GREEN}✅ All prerequisites met${NC}"
echo ""

# Check if Dockerfile exists
if [ ! -f "Dockerfile" ]; then
    echo -e "${RED}❌ Dockerfile not found in current directory${NC}"
    exit 1
fi

# Check if source code exists
if [ ! -d "flink-consumer" ]; then
    echo -e "${RED}❌ flink-consumer directory not found${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Source code and Dockerfile found${NC}"
echo ""

# Build the Docker image for x86_64
echo -e "${YELLOW}Building Docker image for linux/amd64 (x86_64)...${NC}"
echo "This may take 5-10 minutes for the first build..."
echo ""

docker build --platform linux/amd64 \
  -t ${ECR_REPOSITORY}:${IMAGE_TAG} \
  -t ${ECR_REPOSITORY}:$(date +%Y%m%d-%H%M%S) \
  .

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Docker image built successfully${NC}"
else
    echo -e "${RED}❌ Docker build failed${NC}"
    exit 1
fi

echo ""

# Get ECR login token
echo -e "${YELLOW}Authenticating with ECR...${NC}"
aws ecr get-login-password --region ${AWS_REGION} | \
  docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ ECR authentication successful${NC}"
else
    echo -e "${RED}❌ ECR authentication failed${NC}"
    exit 1
fi

echo ""

# Check if ECR repository exists
echo -e "${YELLOW}Checking if ECR repository exists...${NC}"
if ! aws ecr describe-repositories --repository-names ${ECR_REPOSITORY} --region ${AWS_REGION} &> /dev/null; then
    echo -e "${YELLOW}⚠️  ECR repository '${ECR_REPOSITORY}' does not exist${NC}"
    echo -e "${YELLOW}Creating ECR repository...${NC}"
    
    aws ecr create-repository \
      --repository-name ${ECR_REPOSITORY} \
      --region ${AWS_REGION} \
      --image-scanning-configuration scanOnPush=true
    
    echo -e "${GREEN}✅ ECR repository created${NC}"
else
    echo -e "${GREEN}✅ ECR repository exists${NC}"
fi

echo ""

# Tag image for ECR
ECR_IMAGE="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}"
echo -e "${YELLOW}Tagging image for ECR...${NC}"
docker tag ${ECR_REPOSITORY}:${IMAGE_TAG} ${ECR_IMAGE}:${IMAGE_TAG}
docker tag ${ECR_REPOSITORY}:${IMAGE_TAG} ${ECR_IMAGE}:$(date +%Y%m%d-%H%M%S)

echo -e "${GREEN}✅ Image tagged${NC}"
echo ""

# Push to ECR
echo -e "${YELLOW}Pushing image to ECR...${NC}"
docker push ${ECR_IMAGE}:${IMAGE_TAG}
docker push ${ECR_IMAGE}:$(date +%Y%m%d-%H%M%S)

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Image pushed successfully${NC}"
else
    echo -e "${RED}❌ Image push failed${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}======================================"
echo "✅ Build and Push Complete!"
echo "======================================${NC}"
echo ""

echo -e "${YELLOW}Image Details:${NC}"
echo "  Repository: ${ECR_IMAGE}"
echo "  Tags: ${IMAGE_TAG}, $(date +%Y%m%d-%H%M%S)"
echo "  Platform: linux/amd64 (x86_64)"
echo ""

echo -e "${YELLOW}To use this image in Flink deployment:${NC}"
echo "  Update flink-job-deployment.yaml line 9:"
echo "  image: ${ECR_IMAGE}:${IMAGE_TAG}"
echo ""

# Auto-update the deployment YAML if it exists
if [ -f "flink-job-deployment.yaml" ]; then
    echo -e "${YELLOW}Auto-updating flink-job-deployment.yaml...${NC}"
    sed -i.bak "s|image:.*|image: ${ECR_IMAGE}:${IMAGE_TAG}|g" flink-job-deployment.yaml
    echo -e "${GREEN}✅ flink-job-deployment.yaml updated with new image${NC}"
    echo "  Backup saved as: flink-job-deployment.yaml.bak"
else
    echo -e "${YELLOW}⚠️  flink-job-deployment.yaml not found - manual update needed${NC}"
fi

echo ""

echo -e "${YELLOW}To verify image:${NC}"
echo "  aws ecr describe-images --repository-name ${ECR_REPOSITORY} --region ${AWS_REGION}"
echo ""

echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Review flink-job-deployment.yaml"
echo "  2. Deploy: kubectl apply -f flink-job-deployment.yaml"
echo "  3. Monitor: kubectl get pods -n flink-benchmark -w"
echo ""

echo "======================================"

