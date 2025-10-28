#!/bin/bash

echo "======================================"
echo "ClickHouse Full Installation Script"
echo "======================================"
echo "This script will install:"
echo "  1. ClickHouse Operator"
echo "  2. ZooKeeper (3 replicas)"
echo "  3. ClickHouse Cluster (3 shards × 2 replicas = 6 pods)"
echo ""

set -e

# Check prerequisites
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found. Please install kubectl first."
    exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Cannot connect to Kubernetes cluster."
    echo "   Please configure kubectl with: aws eks update-kubeconfig --region us-west-2 --name bench-low-infra"
    exit 1
fi

echo "✅ Prerequisites check passed"
echo ""

# ============================================
# STEP 1: Install ClickHouse Operator
# ============================================
echo "======================================"
echo "STEP 1/3: Installing ClickHouse Operator"
echo "======================================"
echo ""

# Check if operator is already installed
if kubectl get deployment -n kube-system clickhouse-operator &> /dev/null; then
    echo "⚠️  ClickHouse operator already installed. Skipping..."
else
    echo "📦 Installing ClickHouse operator..."
    
    # Install using official manifests
    kubectl apply -f https://raw.githubusercontent.com/Altinity/clickhouse-operator/master/deploy/operator/clickhouse-operator-install-bundle.yaml
    
    echo "⏳ Waiting for operator to be ready..."
    kubectl wait --for=condition=available --timeout=180s deployment/clickhouse-operator -n kube-system
    
    echo "✅ ClickHouse operator installed successfully!"
fi

echo ""

# ============================================
# STEP 2: Deploy ZooKeeper
# ============================================
echo "======================================"
echo "STEP 2/3: Deploying ZooKeeper Cluster"
echo "======================================"
echo ""

# Check if ZooKeeper is already running
if kubectl get statefulset zookeeper -n zoons &> /dev/null; then
    echo "⚠️  ZooKeeper already deployed. Checking status..."
    kubectl get pods -n zoons
else
    echo "📦 Deploying ZooKeeper (3 replicas)..."
    
    # Deploy ZooKeeper using the deploy-zookeeper-all.yaml
    ZOOKEEPER_YAML="./deploy-zookeeper-all.yaml"
    
    if [ ! -f "$ZOOKEEPER_YAML" ]; then
        echo "❌ ZooKeeper deployment file not found at: $ZOOKEEPER_YAML"
        exit 1
    fi
    
    kubectl apply -f "$ZOOKEEPER_YAML"
    
    echo "⏳ Waiting for ZooKeeper pods to be ready (this may take 2-3 minutes)..."
    
    # Wait for all 3 ZooKeeper pods to be ready
    for i in 0 1 2; do
        echo "  Waiting for zookeeper-$i..."
        kubectl wait --for=condition=ready --timeout=180s pod/zookeeper-$i -n zoons 2>/dev/null || echo "  Still starting..."
    done
    
    # Final status check
    echo ""
    echo "📊 ZooKeeper Status:"
    kubectl get pods -n zoons
    
    READY_COUNT=$(kubectl get pods -n zoons -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' | wc -w)
    if [ $READY_COUNT -ge 2 ]; then
        echo "✅ ZooKeeper cluster deployed (${READY_COUNT}/3 pods running - quorum established)"
    else
        echo "⚠️  Only ${READY_COUNT}/3 ZooKeeper pods running. Continuing anyway..."
    fi
fi

echo ""

# ============================================
# STEP 3: Deploy ClickHouse Cluster
# ============================================
echo "======================================"
echo "STEP 3/3: Deploying ClickHouse Cluster"
echo "======================================"
echo ""

# Check if ClickHouse is already running
if kubectl get chi iot-cluster-repl -n clickhouse &> /dev/null; then
    echo "⚠️  ClickHouse cluster already deployed. Checking status..."
    kubectl get pods -n clickhouse
else
    echo "📦 Deploying ClickHouse cluster (3 shards × 2 replicas)..."
    
    # Deploy ClickHouse using the deploy-clickhouse-all.yaml
    CLICKHOUSE_YAML="./deploy-clickhouse-all.yaml"
    
    if [ ! -f "$CLICKHOUSE_YAML" ]; then
        echo "❌ ClickHouse deployment file not found at: $CLICKHOUSE_YAML"
        exit 1
    fi
    
    kubectl apply -f "$CLICKHOUSE_YAML"
    
    echo "⏳ Waiting for ClickHouse installation to complete..."
    echo "   This will provision 6 pods (3 shards × 2 replicas) and may take 5-10 minutes..."
    
    # Wait for ClickHouseInstallation to be created
    sleep 5
    
    # Wait for at least 4 pods to be ready (quorum)
    echo ""
    echo "⏳ Waiting for ClickHouse pods (need at least 4/6 for quorum)..."
    
    for i in {1..60}; do
        READY=$(kubectl get pods -n clickhouse -l clickhouse.altinity.com/app=chop --no-headers 2>/dev/null | grep Running | wc -l)
        echo "  Attempt $i/60: $READY/6 pods running..."
        
        if [ $READY -ge 4 ]; then
            echo "  ✅ Quorum reached ($READY/6 pods)"
            break
        fi
        
        sleep 10
    done
    
    echo ""
    echo "📊 ClickHouse Cluster Status:"
    kubectl get chi -n clickhouse
    echo ""
    kubectl get pods -n clickhouse
    
    # Check if we have enough pods
    READY=$(kubectl get pods -n clickhouse -l clickhouse.altinity.com/app=chop --no-headers 2>/dev/null | grep Running | wc -l)
    if [ $READY -ge 4 ]; then
        echo "✅ ClickHouse cluster deployed successfully ($READY/6 pods running)"
    else
        echo "⚠️  Only $READY/6 ClickHouse pods running. May need more time..."
        echo "   You can check progress with: kubectl get pods -n clickhouse -w"
    fi
fi

echo ""

# ============================================
# STEP 4: Verify Installation
# ============================================
echo "======================================"
echo "Installation Verification"
echo "======================================"
echo ""

echo "🔍 Checking ClickHouse Operator..."
kubectl get deployment clickhouse-operator -n kube-system -o wide

echo ""
echo "🔍 Checking ZooKeeper..."
kubectl get pods -n zoons -o wide

echo ""
echo "🔍 Checking ClickHouse Cluster..."
kubectl get pods -n clickhouse -o wide

echo ""
echo "🔍 Checking ClickHouse Services..."
kubectl get svc -n clickhouse

echo ""

# ============================================
# STEP 5: Test Connectivity
# ============================================
echo "======================================"
echo "Testing ClickHouse Connectivity"
echo "======================================"
echo ""

# Wait a bit for ClickHouse to be fully ready
sleep 5

# Try to connect to ClickHouse
FIRST_POD=$(kubectl get pods -n clickhouse -l clickhouse.altinity.com/app=chop -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -n "$FIRST_POD" ]; then
    echo "🔌 Testing connection to ClickHouse..."
    
    if kubectl exec -n clickhouse $FIRST_POD -- clickhouse-client --query "SELECT version()" 2>/dev/null; then
        echo "✅ ClickHouse is responding!"
        
        # Check ZooKeeper connection
        echo ""
        echo "🔌 Testing ZooKeeper connection from ClickHouse..."
        kubectl exec -n clickhouse $FIRST_POD -- clickhouse-client --query "SELECT * FROM system.zookeeper WHERE path='/'" 2>/dev/null && echo "✅ ZooKeeper is connected!" || echo "⚠️  ZooKeeper not yet connected (may need more time)"
    else
        echo "⚠️  ClickHouse not yet responding. May need more time to initialize."
    fi
else
    echo "⚠️  No ClickHouse pods found. Check deployment status."
fi

echo ""

# ============================================
# Installation Complete
# ============================================
echo "======================================"
echo "✅ Installation Complete!"
echo "======================================"
echo ""
echo "📊 Infrastructure Summary:"
echo "  - ClickHouse Operator: Installed in kube-system"
echo "  - ZooKeeper: 3 replicas in 'zoons' namespace"
echo "  - ClickHouse: 6 pods (3 shards × 2 replicas) in 'clickhouse' namespace"
echo ""
echo "📋 Next Steps:"
echo ""
echo "  1. Run the data loading script:"
echo "     cd /Users/vijayabhaskarv/IOT/datapipeline-0/Flink-Benchmark/low_infra_flink/clickhouse-load"
echo "     ./05-deploy.sh"
echo ""
echo "  2. Monitor data writing:"
echo "     kubectl logs -f deployment/clickhouse-low-rate-writer -n clickhouse"
echo ""
echo "  3. Monitor query benchmark:"
echo "     kubectl logs -f deployment/clickhouse-low-rate-benchmark -n clickhouse"
echo ""
echo "  4. Check data counts:"
echo "     kubectl exec -n clickhouse $FIRST_POD -- clickhouse-client --query 'SELECT count() FROM benchmark.cpu_local'"
echo "     kubectl exec -n clickhouse $FIRST_POD -- clickhouse-client --query 'SELECT count() FROM benchmark.sensors_local'"
echo ""
echo "======================================"

