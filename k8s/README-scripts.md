# IoT Pipeline Management Scripts

These scripts help you easily manage the IoT data pipeline on Kind Kubernetes.

## Scripts Overview

### 1. `create-cluster.sh` 
Creates a Kind Kubernetes cluster for the IoT pipeline.

### 2. `start-pipeline.sh`
Deploys and starts the complete IoT pipeline (assumes cluster exists).

### 3. `stop-pipeline.sh`
Stops and removes all pipeline components.

## Usage

### First Time Setup:
```bash
# 1. Create Kind cluster
./create-cluster.sh

# 2. Start the pipeline
./start-pipeline.sh
```

### Regular Usage (cluster exists):
```bash
# Start pipeline
./start-pipeline.sh

# Stop pipeline
./stop-pipeline.sh

# Start again
./start-pipeline.sh
```

### Complete Cleanup:
```bash
# Stop pipeline
./stop-pipeline.sh

# Delete cluster
kind delete cluster --name iot-pipeline
```

## What Each Script Does

### `create-cluster.sh`:
- Checks if Kind and kubectl are installed
- Creates 3-node Kind cluster with proper configuration
- Sets up kubeconfig at `/tmp/iot-kubeconfig`
- Waits for cluster to be ready

### `start-pipeline.sh`:
- Builds Docker images (producer and Flink consumer JAR)
- Loads images into Kind cluster
- Deploys all Kubernetes resources in order:
  - Namespace
  - Pulsar (message broker)
  - ClickHouse (database)
  - Flink (stream processing)
  - IoT Producer (data generator)
- Initializes ClickHouse tables
- Submits Flink job
- Waits for data flow and shows results
- Sets up port-forwarding for access

### `stop-pipeline.sh`:
- Deletes the entire `iot-pipeline` namespace
- Kills any port-forward processes
- Clean shutdown of all services

## Expected Output

After running `start-pipeline.sh`, you should see:
- ✅ All pods running
- ✅ Flink job processing data
- ✅ Data flowing into ClickHouse
- 🌐 Flink UI accessible at http://localhost:8081

## Quick Commands After Deployment

```bash
# Set kubeconfig
export KUBECONFIG=/tmp/iot-kubeconfig

# Check data count
kubectl exec -n iot-pipeline clickhouse-0 -- clickhouse-client -d iot --query "SELECT COUNT(*) FROM sensor_raw_data"

# View recent data
kubectl exec -n iot-pipeline clickhouse-0 -- clickhouse-client -d iot --query "SELECT * FROM sensor_raw_data ORDER BY timestamp DESC LIMIT 5" --format Pretty

# Check alerts
kubectl exec -n iot-pipeline clickhouse-0 -- clickhouse-client -d iot --query "SELECT alert_type, COUNT(*) FROM sensor_alerts GROUP BY alert_type" --format Pretty

# Check pod status
kubectl get pods -n iot-pipeline

# Check Flink jobs
kubectl exec -n iot-pipeline $(kubectl get pods -n iot-pipeline -l app=flink,component=jobmanager -o jsonpath='{.items[0].metadata.name}') -- flink list
```

## Troubleshooting

If something fails:
1. Check pod logs: `kubectl logs -n iot-pipeline <pod-name>`
2. Check services: `kubectl get svc -n iot-pipeline`
3. Restart pipeline: `./stop-pipeline.sh && ./start-pipeline.sh`

The scripts include error handling and will exit with clear error messages if something goes wrong.