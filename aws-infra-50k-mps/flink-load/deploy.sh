#!/bin/bash
#
# Flink Operator Deployment Script for Existing EKS Cluster
# ===========================================================
# This script deploys Flink Kubernetes Operator on an existing EKS cluster
# 
# PREREQUISITES:
#   - EKS cluster already provisioned (via Terraform in parent directory)
#   - kubectl configured and able to connect to cluster
#   - helm installed locally
#   - cert-manager installed (for webhooks, optional)
#
# USAGE:
#   cd /Users/vijayabhaskarv/IOT/datapipeline-0/Flink-Benchmark/low_infra_flink/flink-load
#   chmod +x deploy.sh
#   ./deploy.sh
#
# ===========================================================

set -e

echo "======================================"
echo "Flink Operator Deployment"
echo "======================================"
echo "This script deploys Flink Kubernetes Operator"
echo "Assumes: EKS cluster already exists"
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
REGION=${AWS_REGION:-us-west-2}
CLUSTER_NAME=${CLUSTER_NAME:-bench-low-infra}
FLINK_OPERATOR_VERSION="1.13.0"

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

command -v kubectl >/dev/null 2>&1 || { echo -e "${RED}kubectl is required but not installed. Aborting.${NC}" >&2; exit 1; }
command -v helm >/dev/null 2>&1 || { echo -e "${RED}helm is required but not installed. Aborting.${NC}" >&2; exit 1; }

echo -e "${GREEN}✅ All prerequisites met!${NC}"
echo ""

# Configure kubectl
echo -e "${YELLOW}Configuring kubectl for cluster: ${CLUSTER_NAME}...${NC}"
aws eks --region ${REGION} update-kubeconfig --name ${CLUSTER_NAME} 2>&1 || true

# Verify connection
echo -e "${YELLOW}Verifying cluster connection...${NC}"
if ! kubectl get nodes &> /dev/null; then
    echo -e "${RED}❌ Cannot connect to Kubernetes cluster!${NC}"
    exit 1
fi

kubectl get nodes
echo -e "${GREEN}✅ Connected to cluster${NC}"
echo ""

# Check/Install cert-manager (optional, for webhooks)
echo -e "${YELLOW}Checking cert-manager...${NC}"
if kubectl get namespace cert-manager &> /dev/null; then
    echo -e "${GREEN}✅ cert-manager already installed${NC}"
else
    echo -e "${YELLOW}Installing cert-manager (for Flink operator webhooks)...${NC}"
    helm repo add jetstack https://charts.jetstack.io
    helm repo update
    
    helm install cert-manager jetstack/cert-manager \
      --namespace cert-manager \
      --create-namespace \
      --version v1.15.0 \
      --set crds.enabled=true \
      --wait
    
    echo -e "${GREEN}✅ cert-manager installed${NC}"
fi
echo ""

# Create flink-operator namespace if it doesn't exist
echo -e "${YELLOW}Creating flink-operator namespace...${NC}"
kubectl create namespace flink-operator --dry-run=client -o yaml | kubectl apply -f -
echo -e "${GREEN}✅ Namespace ready${NC}"
echo ""

# Add Flink Helm repository
echo -e "${YELLOW}Adding Flink Helm repository...${NC}"
helm repo add flink-operator-repo https://downloads.apache.org/flink/flink-kubernetes-operator-${FLINK_OPERATOR_VERSION}/ 2>&1 || \
    echo -e "${YELLOW}⚠️  Repository already exists${NC}"
helm repo update

echo -e "${GREEN}✅ Helm repository added${NC}"
echo ""

# Install or upgrade Flink operator
echo -e "${YELLOW}Installing Flink Kubernetes Operator ${FLINK_OPERATOR_VERSION}...${NC}"

if helm list -n flink-operator | grep -q flink-kubernetes-operator; then
    echo -e "${YELLOW}Flink operator already installed, upgrading...${NC}"
    helm upgrade flink-kubernetes-operator flink-operator-repo/flink-kubernetes-operator \
      --namespace flink-operator \
      --set webhook.create=false \
      --set image.tag=${FLINK_OPERATOR_VERSION} \
      --set resources.requests.memory=512Mi \
      --set resources.requests.cpu=250m \
      --set resources.limits.memory=1Gi \
      --set resources.limits.cpu=500m \
      --wait
else
    echo -e "${YELLOW}Installing Flink operator for the first time...${NC}"
    helm install flink-kubernetes-operator flink-operator-repo/flink-kubernetes-operator \
      --namespace flink-operator \
      --set webhook.create=false \
      --set image.tag=${FLINK_OPERATOR_VERSION} \
      --set resources.requests.memory=512Mi \
      --set resources.requests.cpu=250m \
      --set resources.limits.memory=1Gi \
      --set resources.limits.cpu=500m \
      --wait
fi

echo -e "${GREEN}✅ Flink operator installed${NC}"
echo ""

# Wait for operator to be ready
echo -e "${YELLOW}Waiting for Flink operator pod to be ready...${NC}"
kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=flink-kubernetes-operator \
  -n flink-operator --timeout=180s

echo ""
echo -e "${GREEN}======================================"
echo "✅ Flink Operator Deployment Complete!"
echo "======================================${NC}"
echo ""

# Display status
echo -e "${YELLOW}Flink Operator Status:${NC}"
kubectl get pods -n flink-operator
echo ""

echo -e "${YELLOW}Flink Operator Version:${NC}"
kubectl get deployment -n flink-operator flink-kubernetes-operator \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
echo ""
echo ""

echo -e "${YELLOW}📋 Useful Commands:${NC}"
echo ""
echo "  # View operator logs:"
echo "  kubectl logs -f deployment/flink-kubernetes-operator -n flink-operator"
echo ""
echo "  # Deploy a Flink job:"
echo "  kubectl apply -f your-flink-job.yaml"
echo ""
echo "  # List Flink deployments:"
echo "  kubectl get flinkdeployment -n flink-benchmark"
echo ""
echo "  # Check operator status:"
echo "  kubectl get deployment -n flink-operator"
echo ""
echo "  # Uninstall operator:"
echo "  helm uninstall flink-kubernetes-operator -n flink-operator"
echo ""
echo "======================================"

