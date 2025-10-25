#!/bin/bash
#
# Pulsar Deployment Script for Existing EKS Cluster
# ====================================================
# This script deploys Apache Pulsar using Helm on an existing EKS cluster
# 
# PREREQUISITES:
#   - EKS cluster already provisioned (via Terraform in parent directory)
#   - kubectl configured and able to connect to cluster
#   - helm installed locally
#   - Sufficient nodes for Pulsar components
#
# USAGE:
#   cd /Users/vijayabhaskarv/IOT/datapipeline-0/Flink-Benchmark/low_infra_flink/pulsar-load
#   chmod +x deploy.sh
#   ./deploy.sh
#
# ====================================================

set -e

echo "======================================"
echo "Pulsar Deployment on Existing EKS Cluster"
echo "======================================"
echo "This script deploys Pulsar on an existing EKS cluster"
echo "Assumes: EKS cluster and nodes are already provisioned"
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration - update these to match your cluster
REGION=${AWS_REGION:-us-west-2}
CLUSTER_NAME=${CLUSTER_NAME:-bench-low-infra}

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

command -v kubectl >/dev/null 2>&1 || { echo -e "${RED}kubectl is required but not installed. Aborting.${NC}" >&2; exit 1; }
command -v helm >/dev/null 2>&1 || { echo -e "${RED}helm is required but not installed. Aborting.${NC}" >&2; exit 1; }
command -v aws >/dev/null 2>&1 || { echo -e "${RED}AWS CLI is required but not installed. Aborting.${NC}" >&2; exit 1; }

echo -e "${GREEN}✅ All prerequisites met!${NC}"
echo ""

# Configure kubectl to use existing cluster
echo -e "${YELLOW}Configuring kubectl for cluster: ${CLUSTER_NAME}...${NC}"
aws eks --region ${REGION} update-kubeconfig --name ${CLUSTER_NAME}

# Verify connection
echo -e "${YELLOW}Verifying cluster connection...${NC}"
if ! kubectl get nodes &> /dev/null; then
    echo -e "${RED}❌ Cannot connect to Kubernetes cluster!${NC}"
    echo "   Please ensure:"
    echo "   1. EKS cluster exists"
    echo "   2. kubectl is configured"
    echo "   3. Run: aws eks update-kubeconfig --region ${REGION} --name ${CLUSTER_NAME}"
    exit 1
fi

kubectl get nodes
echo -e "${GREEN}✅ Connected to cluster${NC}"
echo ""

# Wait for nodes to be ready
echo -e "${YELLOW}Waiting for all nodes to be ready...${NC}"
kubectl wait --for=condition=Ready nodes --all --timeout=300s || echo -e "${YELLOW}⚠️  Some nodes not ready yet, continuing...${NC}"
echo ""

# Check if EBS CSI Driver is available (should be installed by Terraform)
echo -e "${YELLOW}Checking EBS CSI Driver...${NC}"
if kubectl get csidriver ebs.csi.aws.com >/dev/null 2>&1; then
    echo -e "${GREEN}✅ EBS CSI driver already installed${NC}"
else
    echo -e "${YELLOW}⚠️  EBS CSI driver not found. Installing...${NC}"
    kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.35" || \
    echo -e "${YELLOW}⚠️  Install via: terraform or EKS addon${NC}"
fi
echo ""

# Create StorageClass if needed (gp3 should already exist from Terraform)
echo -e "${YELLOW}Ensuring gp3 StorageClass exists...${NC}"
if kubectl get storageclass gp3 &> /dev/null; then
    echo -e "${GREEN}✅ gp3 StorageClass already exists${NC}"
else
    echo -e "${YELLOW}Creating gp3 StorageClass...${NC}"
    cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  fsType: ext4
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
EOF
    echo -e "${GREEN}✅ gp3 StorageClass created${NC}"
fi
echo ""

# Verify local Pulsar chart exists
echo -e "${YELLOW}Checking for local Pulsar chart...${NC}"
if [ ! -d "helm/pulsar" ]; then
    echo -e "${RED}Error: Local Pulsar chart not found at helm/pulsar${NC}"
    echo -e "${YELLOW}Please ensure the helm/pulsar chart directory exists in the current directory${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Found local Pulsar chart at helm/pulsar${NC}"

# Install Pulsar
echo -e "${YELLOW}Installing Pulsar (this will take 5-10 minutes)...${NC}"

# Check if values file exists
if [ ! -f "pulsar-values.yaml" ]; then
    echo -e "${YELLOW}⚠️  pulsar-values.yaml not found, using default values from chart${NC}"
    VALUES_ARG=""
else
    echo -e "${GREEN}✅ Using custom values from pulsar-values.yaml${NC}"
    VALUES_ARG="--values pulsar-values.yaml"
fi

# Check if Pulsar is already installed
if helm list -n pulsar | grep -q pulsar; then
    echo -e "${YELLOW}Pulsar is already installed, upgrading...${NC}"
    helm upgrade pulsar helm/pulsar \
      --namespace pulsar \
      $VALUES_ARG \
      --timeout 10m \
      --wait
else
    echo -e "${YELLOW}Installing Pulsar for the first time from local chart...${NC}"
    helm install pulsar helm/pulsar \
      --namespace pulsar \
      --create-namespace \
      $VALUES_ARG \
      --timeout 10m \
      --wait
fi

# Wait for all pods to be ready
echo -e "${YELLOW}Waiting for Pulsar components to be ready...${NC}"
kubectl -n pulsar wait --for=condition=Ready pods --all --timeout=600s

# Get service endpoints
echo ""
echo -e "${GREEN}======================================"
echo "✅ Pulsar Deployment Completed!"
echo "======================================${NC}"
echo ""

echo -e "${YELLOW}Cluster Information:${NC}"
echo "  Cluster Name: ${CLUSTER_NAME}"
echo "  Region: ${REGION}"
echo ""

echo -e "${YELLOW}Pulsar Service Endpoints:${NC}"
PROXY_SERVICE=$(kubectl -n pulsar get svc pulsar-proxy -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
if [ -z "$PROXY_SERVICE" ]; then
    PROXY_SERVICE=$(kubectl -n pulsar get svc pulsar-proxy -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
fi

if [ ! -z "$PROXY_SERVICE" ]; then
    echo "Proxy Service: pulsar://${PROXY_SERVICE}:6650"
    echo "HTTP Service: http://${PROXY_SERVICE}:8080"
fi

GRAFANA_SERVICE=$(kubectl -n pulsar get svc pulsar-grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
if [ -z "$GRAFANA_SERVICE" ]; then
    GRAFANA_SERVICE=$(kubectl -n pulsar get svc pulsar-grafana -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
fi

if [ ! -z "$GRAFANA_SERVICE" ]; then
    echo "Grafana Dashboard: http://${GRAFANA_SERVICE}:3000"
    echo "  Username: admin"
    echo "  Password: admin123 (change this!)"
fi

echo ""
echo -e "${YELLOW}Verify deployment:${NC}"
echo "kubectl -n pulsar get pods"
echo "kubectl -n pulsar get pvc"
echo ""

echo -e "${YELLOW}Test Pulsar:${NC}"
echo "# Create a test topic"
echo "kubectl -n pulsar exec -it pulsar-toolset-0 -- bin/pulsar-admin topics create persistent://public/default/test-topic"
echo ""
echo "# Produce a message"
echo "kubectl -n pulsar exec -it pulsar-toolset-0 -- bin/pulsar-client produce persistent://public/default/test-topic --messages 'Hello Pulsar'"
echo ""
echo "# Consume messages"
echo "kubectl -n pulsar exec -it pulsar-toolset-0 -- bin/pulsar-client consume persistent://public/default/test-topic -s 'test-subscription'"

echo ""
echo -e "${GREEN}Deployment complete!${NC}"