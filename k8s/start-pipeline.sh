#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting IoT Pipeline...${NC}"
echo "========================"

# Set kubeconfig for Kind cluster
export KUBECONFIG=/tmp/iot-kubeconfig

# Check if cluster exists
if ! kubectl get nodes &>/dev/null; then
    echo -e "${RED}Error: Kind cluster 'iot-pipeline' not found or not accessible${NC}"
    echo "Make sure to create the cluster first with the cluster creation script"
    exit 1
fi

echo -e "${BLUE}Using Kind cluster nodes:${NC}"
kubectl get nodes

# Step 1: Build Docker images
echo -e "\n${YELLOW}Step 1: Building Docker images...${NC}"

# Build producer image
echo "Building producer image..."
cd ../producer
if ! docker build -t iot-producer:latest .; then
    echo -e "${RED}Failed to build producer image${NC}"
    exit 1
fi

# Build Flink consumer JAR
echo "Building Flink consumer JAR..."
cd ../flink-consumer
if ! mvn clean package -DskipTests -q; then
    echo -e "${RED}Failed to build Flink consumer JAR${NC}"
    exit 1
fi

# Prepare JAR for mounting
mkdir -p /tmp/flink-jars
cp target/flink-consumer-1.0.0.jar /tmp/flink-jars/

cd ../k8s

# Load producer image into Kind
echo "Loading producer image into Kind..."
if ! kind load docker-image iot-producer:latest --name iot-pipeline; then
    echo -e "${RED}Failed to load producer image into Kind${NC}"
    exit 1
fi

# Step 2: Deploy services
echo -e "\n${YELLOW}Step 2: Deploying services to Kubernetes...${NC}"

# Create namespace
echo "Creating namespace..."
kubectl apply -f namespace.yaml

# Deploy services in order
echo "Deploying Pulsar..."
kubectl apply -f pulsar.yaml

echo "Deploying ClickHouse..."
kubectl apply -f clickhouse.yaml

echo "Deploying Flink..."
kubectl apply -f flink.yaml

# Step 3: Wait for services to be ready
echo -e "\n${YELLOW}Step 3: Waiting for services to be ready...${NC}"

echo "Waiting for Pulsar..."
kubectl wait --namespace=iot-pipeline --for=condition=ready pod --selector=app=pulsar --timeout=120s

echo "Waiting for ClickHouse..."
kubectl wait --namespace=iot-pipeline --for=condition=ready pod --selector=app=clickhouse --timeout=120s

echo "Waiting for Flink JobManager..."
kubectl wait --namespace=iot-pipeline --for=condition=ready pod --selector=app=flink,component=jobmanager --timeout=120s

echo "Waiting for Flink TaskManagers..."
kubectl wait --namespace=iot-pipeline --for=condition=ready pod --selector=app=flink,component=taskmanager --timeout=120s

# Step 4: Initialize ClickHouse
echo -e "\n${YELLOW}Step 4: Initializing ClickHouse database...${NC}"
sleep 5  # Give ClickHouse time to fully start

# Create database and tables
kubectl exec -n iot-pipeline clickhouse-0 -- clickhouse-client --query "CREATE DATABASE IF NOT EXISTS iot" || {
    echo -e "${RED}Failed to create ClickHouse database${NC}"
    exit 1
}

kubectl exec -n iot-pipeline clickhouse-0 -- clickhouse-client -d iot --query "
CREATE TABLE IF NOT EXISTS sensor_raw_data (
    sensor_id String,
    sensor_type String,
    location String,
    temperature Float64,
    humidity Float64,
    pressure Float64,
    battery_level Float64,
    status String,
    timestamp DateTime,
    manufacturer String,
    model String,
    firmware_version String,
    latitude Float64,
    longitude Float64
) ENGINE = MergeTree()
ORDER BY (sensor_id, timestamp);

CREATE TABLE IF NOT EXISTS sensor_alerts (
    sensor_id String,
    sensor_type String,
    location String,
    temperature Float64,
    humidity Float64,
    battery_level Float64,
    alert_type String,
    alert_time DateTime
) ENGINE = MergeTree()
ORDER BY (sensor_id, alert_time);
" || {
    echo -e "${RED}Failed to create ClickHouse tables${NC}"
    exit 1
}

# Step 5: Deploy producer
echo -e "\n${YELLOW}Step 5: Deploying IoT Producer...${NC}"
kubectl apply -f producer.yaml

# Wait for producer
kubectl wait --namespace=iot-pipeline --for=condition=ready pod --selector=app=iot-producer --timeout=60s

# Step 6: Submit Flink job
echo -e "\n${YELLOW}Step 6: Submitting Flink job...${NC}"

# Copy JAR to JobManager
JOB_MANAGER_POD=$(kubectl get pods -n iot-pipeline -l app=flink,component=jobmanager -o jsonpath='{.items[0].metadata.name}')
kubectl cp /tmp/flink-jars/flink-consumer-1.0.0.jar iot-pipeline/$JOB_MANAGER_POD:/tmp/flink-consumer-1.0.0.jar

# Submit job
SUBMIT_OUTPUT=$(kubectl exec -n iot-pipeline $JOB_MANAGER_POD -- bash -c '
export PULSAR_URL=pulsar://pulsar:6650
export CLICKHOUSE_URL=jdbc:clickhouse://clickhouse:8123/iot
export PULSAR_TOPIC=persistent://public/default/iot-sensor-data
flink run --detached --class com.iot.pipeline.flink.JDBCFlinkConsumer /tmp/flink-consumer-1.0.0.jar
' 2>&1)

if echo "$SUBMIT_OUTPUT" | grep -q "Job has been submitted"; then
    JOB_ID=$(echo "$SUBMIT_OUTPUT" | grep -o "JobID [a-f0-9]\{32\}" | cut -d' ' -f2)
    echo -e "${GREEN}Flink job submitted successfully with JobID: $JOB_ID${NC}"
else
    echo -e "${RED}Failed to submit Flink job:${NC}"
    echo "$SUBMIT_OUTPUT"
    exit 1
fi

# Step 7: Verify deployment
echo -e "\n${YELLOW}Step 7: Verifying deployment...${NC}"
sleep 10

echo -e "${BLUE}Pod status:${NC}"
kubectl get pods -n iot-pipeline

echo -e "\n${BLUE}Flink job status:${NC}"
kubectl exec -n iot-pipeline $JOB_MANAGER_POD -- flink list

# Step 8: Wait for data and show results
echo -e "\n${YELLOW}Step 8: Waiting for data flow...${NC}"
echo "Waiting 30 seconds for data to be processed..."
sleep 30

# Check data
RAW_COUNT=$(kubectl exec -n iot-pipeline clickhouse-0 -- clickhouse-client -d iot --query "SELECT COUNT(*) FROM sensor_raw_data" 2>/dev/null)
ALERT_COUNT=$(kubectl exec -n iot-pipeline clickhouse-0 -- clickhouse-client -d iot --query "SELECT COUNT(*) FROM sensor_alerts" 2>/dev/null)

echo -e "\n${GREEN}Deployment Complete!${NC}"
echo "===================="
echo -e "\n${BLUE}Data Flow Status:${NC}"
echo "Sensor readings: $RAW_COUNT"
echo "Alerts generated: $ALERT_COUNT"

if [ "$RAW_COUNT" -gt 0 ]; then
    echo -e "\n${GREEN}✅ Pipeline is working! Data is flowing successfully.${NC}"
    
    echo -e "\n${BLUE}Sample data:${NC}"
    kubectl exec -n iot-pipeline clickhouse-0 -- clickhouse-client -d iot --query "SELECT * FROM sensor_raw_data ORDER BY timestamp DESC LIMIT 3" --format Pretty
    
    if [ "$ALERT_COUNT" -gt 0 ]; then
        echo -e "\n${BLUE}Alert distribution:${NC}"
        kubectl exec -n iot-pipeline clickhouse-0 -- clickhouse-client -d iot --query "SELECT alert_type, COUNT(*) as count FROM sensor_alerts GROUP BY alert_type" --format Pretty
    fi
else
    echo -e "\n${YELLOW}⏳ Pipeline deployed but no data yet. Wait a few more minutes for data to flow.${NC}"
fi

# Step 9: Setup port forwarding
echo -e "\n${YELLOW}Step 9: Setting up access...${NC}"

# Kill any existing port-forwards
pkill -f "kubectl port-forward" 2>/dev/null || true

# Start port-forwards in background
nohup kubectl port-forward -n iot-pipeline svc/flink-jobmanager 8081:8081 > /dev/null 2>&1 &
FLINK_PF_PID=$!
sleep 2  # Give port-forward time to establish

echo -e "\n${GREEN}🎉 IoT Pipeline Started Successfully!${NC}"
echo "===================================="

echo -e "\n${BLUE}Access Services:${NC}"
echo "• Flink UI: http://localhost:8081"
echo "• ClickHouse: kubectl exec -n iot-pipeline clickhouse-0 -- clickhouse-client -d iot"
echo "• Pulsar Admin: kubectl port-forward -n iot-pipeline svc/pulsar 8080:8080"

echo -e "\n${BLUE}Monitor Data:${NC}"
echo "export KUBECONFIG=/tmp/iot-kubeconfig"
echo "kubectl exec -n iot-pipeline clickhouse-0 -- clickhouse-client -d iot --query \"SELECT COUNT(*) FROM sensor_raw_data\""

echo -e "\n${BLUE}Stop Pipeline:${NC}"
echo "./stop-pipeline.sh"

echo -e "\n${GREEN}Pipeline is now running and processing data!${NC} 🚀"