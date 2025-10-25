#!/bin/bash

echo "======================================"
echo "ClickHouse Low-Rate Data Loading"
echo "======================================"

set -e

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found. Please install kubectl first."
    exit 1
fi

# Check if ClickHouse is running
echo "🔍 Checking ClickHouse cluster status..."
if ! kubectl get pods -n clickhouse | grep -q "Running"; then
    echo "❌ ClickHouse cluster is not running!"
    echo "   Please deploy ClickHouse first using:"
    echo "   kubectl apply -f ../clickhouse-benchmark/clickhouse_updated_k8script/deploy-clickhouse-all.yaml"
    exit 1
fi

echo "✅ ClickHouse cluster is running"

# Create ConfigMap for Python scripts (in clickhouse namespace)
echo ""
echo "📝 Creating Python scripts ConfigMap..."
kubectl create configmap clickhouse-low-rate-scripts-py \
    --from-file=02-low-rate-writer.py \
    --from-file=03-low-rate-benchmark.py \
    -n clickhouse \
    --dry-run=client -o yaml | kubectl apply -f -

# Create schema on ALL ClickHouse pods using the dedicated script
echo ""
echo "🗄️  Creating database schema on all ClickHouse pods using 00-create-schema-all-replicas.sh..."

# Check if the schema script exists
if [ ! -f "00-create-schema-all-replicas.sh" ]; then
    echo "❌ Schema script not found: 00-create-schema-all-replicas.sh"
    echo "Please run this script from the clickhouse-load directory"
    exit 1
fi

# Make sure the script is executable
chmod +x 00-create-schema-all-replicas.sh

# Execute the schema creation script
echo "📝 Executing schema creation script..."
if ./00-create-schema-all-replicas.sh; then
    echo "✅ Schema created successfully on all pods!"
else
    echo "❌ Failed to create schema on some pods"
    exit 1
fi

# Deploy low-rate writer
echo ""
echo "📤 Deploying low-rate data writer..."
echo "🧹 Deleting existing writer deployment if present..."
kubectl delete deployment clickhouse-low-rate-writer -n clickhouse --ignore-not-found=true

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: clickhouse-low-rate-writer
  namespace: clickhouse
  labels:
    app: clickhouse-low-rate-writer
spec:
  replicas: 1
  selector:
    matchLabels:
      app: clickhouse-low-rate-writer
  template:
    metadata:
      labels:
        app: clickhouse-low-rate-writer
    spec:
      containers:
      - name: writer
        image: python:3.9-slim
        command: ["python3", "/app/02-low-rate-writer.py"]
        env:
        - name: CLICKHOUSE_HOST
          value: "clickhouse-iot-cluster-repl.clickhouse.svc.cluster.local"
        - name: CLICKHOUSE_PORT
          value: "8123"
        - name: CLICKHOUSE_DB
          value: "benchmark"
        - name: CLICKHOUSE_USER
          value: "default"
        - name: CLICKHOUSE_PASSWORD
          value: ""
        - name: PYTHONUNBUFFERED
          value: "1"
        resources:
          requests:
            cpu: "200m"
            memory: "256Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"
        volumeMounts:
        - name: app
          mountPath: /app
      volumes:
      - name: app
        configMap:
          name: clickhouse-low-rate-scripts-py
          defaultMode: 0755
EOF

echo "⏳ Waiting for writer pod to be ready..."
kubectl wait --for=condition=ready --timeout=120s pod -l app=clickhouse-low-rate-writer -n clickhouse

# Deploy benchmark query pod (continuous run)
echo ""
echo "📊 Deploying continuous benchmark query pod..."
echo "🧹 Deleting existing benchmark deployment if present..."
kubectl delete deployment clickhouse-low-rate-benchmark -n clickhouse --ignore-not-found=true

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: clickhouse-low-rate-benchmark
  namespace: clickhouse
  labels:
    app: clickhouse-low-rate-benchmark
spec:
  replicas: 1
  selector:
    matchLabels:
      app: clickhouse-low-rate-benchmark
  template:
    metadata:
      labels:
        app: clickhouse-low-rate-benchmark
    spec:
      containers:
      - name: benchmark
        image: python:3.9-slim
        command: ['python3', '/app/03-low-rate-benchmark.py']
        args: ['--qps=10', '--workers=2', '--duration=86400']
        env:
        - name: CLICKHOUSE_HOST
          value: clickhouse-iot-cluster-repl.clickhouse.svc.cluster.local
        - name: CLICKHOUSE_PORT
          value: '8123'
        - name: PYTHONUNBUFFERED
          value: '1'
        resources:
          requests:
            cpu: "200m"
            memory: "256Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"
        volumeMounts:
        - name: app
          mountPath: /app
      volumes:
      - name: app
        configMap:
          name: clickhouse-low-rate-scripts-py
          defaultMode: 0755
EOF

if [ $? -eq 0 ]; then
  echo "✅ Benchmark deployment created successfully!"
else
  echo "⚠️  Failed to create benchmark deployment"
fi

echo "⏳ Waiting for benchmark pod to be ready..."
kubectl wait --for=condition=ready --timeout=120s pod -l app=clickhouse-low-rate-benchmark -n clickhouse 2>/dev/null || echo "⚠️  Benchmark pod still starting..."

echo ""
echo "======================================"
echo "✅ Deployment Complete!"
echo "======================================"
echo ""
echo "📊 Status:"
kubectl get pods -l app=clickhouse-low-rate-writer -n clickhouse
echo ""
kubectl get pods -l app=clickhouse-low-rate-benchmark -n clickhouse
echo ""
echo "📋 Useful Commands:"
echo ""
echo "  # View writer logs (continuous, ~25 rec/sec):"
echo "  kubectl logs -f deployment/clickhouse-low-rate-writer -n clickhouse"
echo ""
echo "  # View benchmark query logs (continuous, ~10 QPS):"
echo "  kubectl logs -f deployment/clickhouse-low-rate-benchmark -n clickhouse"
echo ""
echo "  # Check data counts in ClickHouse:"
echo "  kubectl exec -n clickhouse chi-iot-cluster-repl-iot-cluster-0-0-0 -- clickhouse-client --query 'SELECT count() FROM benchmark.sensors_local'"
echo "  kubectl exec -n clickhouse chi-iot-cluster-repl-iot-cluster-0-0-0 -- clickhouse-client --query 'SELECT count() FROM benchmark.cpu_local'"
echo ""
echo "  # Stop/Start writer:"
echo "  kubectl scale deployment clickhouse-low-rate-writer --replicas=0 -n clickhouse  # Stop"
echo "  kubectl scale deployment clickhouse-low-rate-writer --replicas=1 -n clickhouse  # Start"
echo ""
echo "  # Stop/Start benchmark:"
echo "  kubectl scale deployment clickhouse-low-rate-benchmark --replicas=0 -n clickhouse  # Stop"
echo "  kubectl scale deployment clickhouse-low-rate-benchmark --replicas=1 -n clickhouse  # Start"
echo ""
echo "======================================"

