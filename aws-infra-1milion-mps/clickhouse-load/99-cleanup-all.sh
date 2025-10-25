#!/bin/bash

echo "======================================"
echo "ClickHouse Infrastructure Cleanup"
echo "======================================"
echo ""
echo "⚠️  WARNING: This will delete:"
echo "  - Data loading pods (writer & benchmark)"
echo "  - ClickHouse cluster (all 6 pods)"
echo "  - ZooKeeper cluster (all 3 pods)"
echo "  - All data in the benchmark database"
echo ""
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "❌ Cleanup cancelled."
    exit 0
fi

echo ""
echo "Starting cleanup..."
echo ""

set +e  # Don't exit on errors during cleanup

# ============================================
# STEP 1: Delete Data Loading Pods
# ============================================
echo "======================================"
echo "STEP 1/4: Deleting Data Loading Pods"
echo "======================================"
echo ""

echo "🧹 Deleting writer and benchmark deployments..."
kubectl delete deployment clickhouse-low-rate-writer -n clickhouse --ignore-not-found=true
kubectl delete deployment clickhouse-low-rate-benchmark -n clickhouse --ignore-not-found=true

echo "🧹 Deleting ConfigMaps..."
kubectl delete configmap clickhouse-low-rate-scripts-py -n clickhouse --ignore-not-found=true
kubectl delete configmap clickhouse-low-rate-scripts-py --ignore-not-found=true

echo "✅ Data loading pods cleaned up"
echo ""

# ============================================
# STEP 2: Delete ClickHouse Cluster
# ============================================
echo "======================================"
echo "STEP 2/4: Deleting ClickHouse Cluster"
echo "======================================"
echo ""

echo "🧹 Deleting ClickHouse installation..."
kubectl delete chi iot-cluster-repl -n clickhouse --ignore-not-found=true

echo "⏳ Waiting for ClickHouse pods to terminate (up to 2 minutes)..."
kubectl wait --for=delete pod -l clickhouse.altinity.com/chi=iot-cluster-repl -n clickhouse --timeout=120s 2>/dev/null || echo "  Timeout waiting, continuing..."

echo "🧹 Deleting ClickHouse PVCs..."
kubectl delete pvc -n clickhouse -l clickhouse.altinity.com/chi=iot-cluster-repl --ignore-not-found=true

echo "🧹 Deleting clickhouse namespace..."
kubectl delete namespace clickhouse --ignore-not-found=true --wait=false

echo "✅ ClickHouse cluster deleted"
echo ""

# ============================================
# STEP 3: Delete ZooKeeper
# ============================================
echo "======================================"
echo "STEP 3/4: Deleting ZooKeeper Cluster"
echo "======================================"
echo ""

echo "🧹 Deleting ZooKeeper StatefulSet..."
kubectl delete statefulset zookeeper -n zoons --ignore-not-found=true

echo "🧹 Deleting ZooKeeper services..."
kubectl delete svc zookeeper zookeepers -n zoons --ignore-not-found=true

echo "🧹 Deleting ZooKeeper PDB..."
kubectl delete pdb zookeeper-pod-disruption-budget -n zoons --ignore-not-found=true

echo "🧹 Deleting ZooKeeper PVCs..."
kubectl delete pvc -n zoons -l app=zookeeper --ignore-not-found=true

echo "🧹 Deleting zoons namespace..."
kubectl delete namespace zoons --ignore-not-found=true --wait=false

echo "✅ ZooKeeper deleted"
echo ""

# ============================================
# STEP 4: Delete ClickHouse Operator (Optional)
# ============================================
echo "======================================"
echo "STEP 4/4: Deleting ClickHouse Operator"
echo "======================================"
echo ""

read -p "Do you want to delete the ClickHouse operator as well? (yes/no): " DELETE_OPERATOR

if [ "$DELETE_OPERATOR" = "yes" ]; then
    echo "🧹 Deleting ClickHouse operator..."
    kubectl delete -f https://raw.githubusercontent.com/Altinity/clickhouse-operator/master/deploy/operator/clickhouse-operator-install-bundle.yaml 2>/dev/null || echo "  Operator deletion failed or already deleted"
    echo "✅ ClickHouse operator deleted"
else
    echo "⏩ Skipping operator deletion (can be reused for future deployments)"
fi

echo ""

# ============================================
# Cleanup Complete
# ============================================
echo "======================================"
echo "✅ Cleanup Complete!"
echo "======================================"
echo ""
echo "📊 Remaining Resources:"
echo ""

echo "Namespaces:"
kubectl get namespace clickhouse zoons 2>/dev/null || echo "  ✅ All cleaned up"

echo ""
echo "PVCs (should be empty):"
kubectl get pvc --all-namespaces | grep -E "clickhouse|zoons" || echo "  ✅ All PVCs deleted"

echo ""
echo "📋 What's Left:"
echo "  - EKS Cluster (use 'terraform destroy' to remove)"
echo "  - EC2 Nodes (6 total - will be removed with terraform destroy)"
echo "  - VPC and Networking (managed by Terraform)"
echo ""
echo "🚀 To completely remove AWS infrastructure:"
echo "   cd /Users/vijayabhaskarv/IOT/datapipeline-0/Flink-Benchmark/low_infra_flink"
echo "   terraform destroy -auto-approve"
echo ""
echo "======================================"

