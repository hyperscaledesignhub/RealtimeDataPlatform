#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}IoT Pipeline - Kind Kubernetes Deployment${NC}"
echo "=========================================="

# Check if kind is installed
if ! command -v kind &> /dev/null; then
    echo -e "${RED}Error: kind is not installed${NC}"
    echo "Install kind: brew install kind (Mac) or check https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
    exit 1
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed${NC}"
    echo "Install kubectl: brew install kubectl (Mac)"
    exit 1
fi

# Step 1: Create Kind cluster
echo -e "\n${YELLOW}Step 1: Creating Kind cluster...${NC}"
kind create cluster --config kind-cluster-config.yaml

# Wait for cluster to be ready
echo -e "${YELLOW}Waiting for cluster to be ready...${NC}"
kubectl wait --for=condition=Ready nodes --all --timeout=60s

# Step 2: Build and load Docker images
echo -e "\n${YELLOW}Step 2: Building Docker images...${NC}"

# Build producer image
echo "Building producer image..."
cd ../producer
docker build -t iot-producer:latest .

# Build Flink consumer JAR
echo "Building Flink consumer JAR..."
cd ../flink-consumer
mvn clean package -DskipTests

# Create directory for JAR mounting
mkdir -p /tmp/flink-jars
cp target/flink-consumer-1.0.0.jar /tmp/flink-jars/

cd ../k8s

# Load producer image into Kind
echo "Loading producer image into Kind..."
kind load docker-image iot-producer:latest --name iot-pipeline

# Step 3: Deploy services
echo -e "\n${YELLOW}Step 3: Deploying services to Kubernetes...${NC}"

# Create namespace
echo "Creating namespace..."
kubectl apply -f namespace.yaml

# Deploy Pulsar
echo "Deploying Pulsar..."
kubectl apply -f pulsar.yaml

# Deploy ClickHouse
echo "Deploying ClickHouse..."
kubectl apply -f clickhouse.yaml

# Deploy Flink
echo "Deploying Flink..."
kubectl apply -f flink.yaml

# Wait for services to be ready
echo -e "\n${YELLOW}Waiting for services to be ready...${NC}"
kubectl wait --namespace=iot-pipeline --for=condition=ready pod --selector=app=pulsar --timeout=120s
kubectl wait --namespace=iot-pipeline --for=condition=ready pod --selector=app=clickhouse --timeout=120s
kubectl wait --namespace=iot-pipeline --for=condition=ready pod --selector=app=flink,component=jobmanager --timeout=120s
kubectl wait --namespace=iot-pipeline --for=condition=ready pod --selector=app=flink,component=taskmanager --timeout=120s

# Initialize ClickHouse
echo -e "\n${YELLOW}Initializing ClickHouse database...${NC}"
sleep 10  # Give ClickHouse time to fully start
kubectl exec -n iot-pipeline clickhouse-0 -- clickhouse-client --query "SOURCE /docker-entrypoint-initdb.d/init.sql" || true

# Step 4: Deploy producer
echo -e "\n${YELLOW}Step 4: Deploying IoT Producer...${NC}"
kubectl apply -f producer.yaml

# Step 5: Submit Flink job
echo -e "\n${YELLOW}Step 5: Submitting Flink job...${NC}"
kubectl apply -f flink-job.yaml

# Wait a bit for everything to stabilize
sleep 10

# Step 6: Show status
echo -e "\n${GREEN}Deployment Complete!${NC}"
echo "=================="
echo -e "\n${YELLOW}Access Services via port-forward:${NC}"
echo "# Pulsar Admin:"
echo "kubectl port-forward -n iot-pipeline svc/pulsar 8080:8080"
echo ""
echo "# ClickHouse:"
echo "kubectl port-forward -n iot-pipeline svc/clickhouse 8123:8123"
echo ""
echo "# Flink UI:"
echo "kubectl port-forward -n iot-pipeline svc/flink-jobmanager 8081:8081"

echo -e "\n${YELLOW}Check pod status:${NC}"
kubectl get pods -n iot-pipeline

echo -e "\n${YELLOW}Check services:${NC}"
kubectl get svc -n iot-pipeline

echo -e "\n${YELLOW}Useful commands:${NC}"
echo "# Check logs:"
echo "kubectl logs -n iot-pipeline -l app=iot-producer"
echo "kubectl logs -n iot-pipeline -l app=flink,component=jobmanager"
echo ""
echo "# Access ClickHouse CLI:"
echo "kubectl exec -it -n iot-pipeline clickhouse-0 -- clickhouse-client -d iot"
echo ""
echo "# Check data in ClickHouse:"
echo "kubectl exec -n iot-pipeline clickhouse-0 -- clickhouse-client -d iot --query 'SELECT COUNT(*) FROM sensor_raw_data'"
echo ""
echo "# Delete cluster when done:"
echo "kind delete cluster --name iot-pipeline"