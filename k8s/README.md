# IoT Pipeline on Kubernetes (Kind)

This directory contains Kubernetes manifests to deploy the IoT pipeline on a local Kind cluster.

## Prerequisites

1. Install Kind:
```bash
# macOS
brew install kind

# Linux
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
```

2. Install kubectl:
```bash
# macOS
brew install kubectl

# Linux
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

## Quick Start

```bash
# Deploy everything
./deploy-kind.sh
```

## Manual Deployment

1. Create Kind cluster:
```bash
kind create cluster --config kind-cluster-config.yaml
```

2. Build and load images:
```bash
# Build producer
cd ../producer
docker build -t iot-producer:latest .
kind load docker-image iot-producer:latest --name iot-pipeline

# Build Flink JAR
cd ../flink-consumer
mvn clean package -DskipTests
mkdir -p /tmp/flink-jars
cp target/flink-consumer-1.0.0.jar /tmp/flink-jars/
```

3. Deploy services:
```bash
kubectl apply -f namespace.yaml
kubectl apply -f pulsar.yaml
kubectl apply -f clickhouse.yaml
kubectl apply -f flink.yaml
kubectl apply -f producer.yaml
kubectl apply -f flink-job.yaml
```

## Access Services

Services use ClusterIP for internal communication only. Use port-forward to access:

```bash
# Pulsar Admin UI
kubectl port-forward -n iot-pipeline svc/pulsar 8080:8080
# Access at: http://localhost:8080

# ClickHouse HTTP Interface
kubectl port-forward -n iot-pipeline svc/clickhouse 8123:8123
# Access at: http://localhost:8123

# Flink Web UI
kubectl port-forward -n iot-pipeline svc/flink-jobmanager 8081:8081
# Access at: http://localhost:8081
```

Run each port-forward in a separate terminal or add `&` to run in background.

## Verify Data Flow

```bash
# Check ClickHouse data
kubectl exec -n iot-pipeline clickhouse-0 -- \
  clickhouse-client -d iot --query "SELECT COUNT(*) FROM sensor_raw_data"

# Check alerts
kubectl exec -n iot-pipeline clickhouse-0 -- \
  clickhouse-client -d iot --query "SELECT alert_type, COUNT(*) FROM sensor_alerts GROUP BY alert_type"
```

## Monitor Logs

```bash
# Producer logs
kubectl logs -n iot-pipeline -l app=iot-producer -f

# Flink JobManager logs
kubectl logs -n iot-pipeline -l app=flink,component=jobmanager -f

# Pulsar logs
kubectl logs -n iot-pipeline -l app=pulsar -f
```

## Troubleshooting

### Check pod status
```bash
kubectl get pods -n iot-pipeline
kubectl describe pod <pod-name> -n iot-pipeline
```

### Restart a service
```bash
kubectl rollout restart deployment/iot-producer -n iot-pipeline
kubectl delete pod <pod-name> -n iot-pipeline
```

### Access container shell
```bash
kubectl exec -it -n iot-pipeline clickhouse-0 -- bash
kubectl exec -it -n iot-pipeline pulsar-0 -- bash
```

## Architecture

```
┌─────────────┐     ┌─────────────┐     ┌──────────────┐     ┌──────────────┐
│   Producer  │────▶│   Pulsar    │────▶│ Flink Cluster│────▶│  ClickHouse  │
│  (1 pod)    │     │ (StatefulSet)│     │  (2+ pods)   │     │ (StatefulSet)│
└─────────────┘     └─────────────┘     └──────────────┘     └──────────────┘
                           │                      │                    │
                           ▼                      ▼                    ▼
                     NodePort:30650         NodePort:30081      NodePort:30123
                     NodePort:30080           (Flink UI)         (HTTP API)
                     (Admin UI)
```

## Cleanup

```bash
# Delete cluster
kind delete cluster --name iot-pipeline

# Remove temp files
rm -rf /tmp/flink-jars
```

## Configuration

### Scaling
- Increase TaskManager replicas in `flink.yaml`
- Increase producer replicas in `producer.yaml`

### Resources
- Adjust memory/CPU limits in each YAML file
- Modify storage sizes in StatefulSet volumeClaimTemplates

### Persistence
- Data persists across pod restarts via PersistentVolumeClaims
- ClickHouse: 10Gi storage
- Pulsar: 5Gi storage