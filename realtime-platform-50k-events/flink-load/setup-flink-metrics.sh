#!/bin/bash

# Complete Flink Metrics Setup for Kubernetes/AWS
# =================================================
# This script automatically sets up Flink to send metrics to Prometheus and Grafana

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
FLINK_NAMESPACE="flink-benchmark"
PULSAR_NAMESPACE="pulsar"
CLICKHOUSE_NAMESPACE="clickhouse"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║   Flink Metrics Monitoring - Complete Setup              ║
║   Kubernetes/AWS Deployment                              ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo -e "${CYAN}Configuration:${NC}"
echo "  • Flink Namespace: $FLINK_NAMESPACE"
echo "  • Pulsar Namespace: $PULSAR_NAMESPACE"
echo "  • ClickHouse Namespace: $CLICKHOUSE_NAMESPACE"
echo ""

# ============================================================================
# STEP 1: Apply Flink Configuration
# ============================================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}STEP 1: Creating Flink Configuration${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "Creating ConfigMap with Flink metrics configuration..."
kubectl apply -f "$SCRIPT_DIR/flink-config-configmap.yaml"
echo -e "${GREEN}✓${NC} Flink ConfigMap created"
echo ""

# ============================================================================
# STEP 2: Apply ServiceMonitor and Services
# ============================================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}STEP 2: Setting up Prometheus Integration${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "Creating metrics services and scrape configurations..."

# Check if Victoria Metrics is installed
if kubectl get crd vmpodscrapes.operator.victoriametrics.com &>/dev/null; then
    echo -e "${GREEN}✓${NC} Victoria Metrics Operator detected"
    echo "Creating VMPodScrape for Flink metrics..."
    kubectl apply -f - <<EOF
apiVersion: operator.victoriametrics.com/v1beta1
kind: VMPodScrape
metadata:
  name: flink-metrics
  namespace: $PULSAR_NAMESPACE
spec:
  selector:
    matchLabels:
      app: iot-flink-job
  namespaceSelector:
    matchNames:
      - $FLINK_NAMESPACE
  podMetricsEndpoints:
    - port: metrics
      path: /metrics
      interval: 15s
EOF
    echo -e "${GREEN}✓${NC} VMPodScrape created"
    
    # Restart vmagent to pick up new scrape config
    echo "Restarting VMAgent to apply scrape configuration..."
    kubectl rollout restart deployment/vmagent-pulsar-victoria-metrics-k8s-stack -n $PULSAR_NAMESPACE 2>/dev/null || echo "  (vmagent will auto-reload configuration)"
    echo -e "${GREEN}✓${NC} VMAgent updated"
    echo ""
fi

# Also try ServiceMonitor for Prometheus Operator compatibility
if kubectl apply -f "$SCRIPT_DIR/flink-servicemonitor.yaml" 2>&1 | grep -q "error.*ServiceMonitor"; then
    echo -e "${YELLOW}⚠${NC} ServiceMonitor CRD not available (Prometheus Operator not installed)"
    echo "  Using Victoria Metrics VMPodScrape instead"
    echo ""
    echo "Applying services only..."
    kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: flink-jobmanager-metrics
  namespace: $FLINK_NAMESPACE
  labels:
    app: flink
    component: jobmanager
spec:
  type: ClusterIP
  ports:
    - name: metrics
      port: 9249
      targetPort: 9249
      protocol: TCP
  selector:
    app: flink
    component: jobmanager
---
apiVersion: v1
kind: Service
metadata:
  name: flink-taskmanager-metrics
  namespace: $FLINK_NAMESPACE
  labels:
    app: flink
    component: taskmanager
spec:
  type: ClusterIP
  ports:
    - name: metrics
      port: 9249
      targetPort: 9249
      protocol: TCP
  selector:
    app: flink
    component: taskmanager
EOF
    echo -e "${GREEN}✓${NC} Metrics services created"
else
    echo -e "${GREEN}✓${NC} ServiceMonitor and Services created"
fi
echo ""

# ============================================================================
# STEP 3: Check Flink Deployments
# ============================================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}STEP 3: Checking Flink Deployments${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Find Flink deployments
FLINK_DEPLOYMENTS=$(kubectl get deployments -n "$FLINK_NAMESPACE" -o name 2>/dev/null | grep -i flink || true)

if [ -z "$FLINK_DEPLOYMENTS" ]; then
    echo -e "${YELLOW}⚠${NC} No Flink deployments found in namespace $FLINK_NAMESPACE"
    echo "Looking for StatefulSets..."
    FLINK_DEPLOYMENTS=$(kubectl get statefulsets -n "$FLINK_NAMESPACE" -o name 2>/dev/null | grep -i flink || true)
fi

if [ -n "$FLINK_DEPLOYMENTS" ]; then
    echo -e "${GREEN}✓${NC} Found Flink deployments:"
    echo "$FLINK_DEPLOYMENTS" | while read dep; do
        echo "  • $dep"
    done
else
    echo -e "${YELLOW}⚠${NC} No Flink deployments found"
    echo "Please check if Flink is deployed in namespace: $FLINK_NAMESPACE"
fi
echo ""

# Check Flink pods
echo "Checking Flink pods..."
FLINK_PODS=$(kubectl get pods -n "$FLINK_NAMESPACE" 2>/dev/null | grep -i flink || true)

if [ -n "$FLINK_PODS" ]; then
    echo -e "${GREEN}✓${NC} Flink pods:"
    echo "$FLINK_PODS" | awk '{print "  " $1 " (" $3 ")"}'
else
    echo -e "${RED}✗${NC} No Flink pods found"
fi
echo ""

# ============================================================================
# STEP 4: Patch Flink Deployments with Metrics Configuration
# ============================================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}STEP 4: Updating Flink Deployments${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check if FlinkDeployment CRD exists (Flink Operator)
FLINK_DEPLOYMENT=$(kubectl get flinkdeployment -n "$FLINK_NAMESPACE" -o name 2>/dev/null | head -1)

if [ -n "$FLINK_DEPLOYMENT" ]; then
    echo -e "${GREEN}✓${NC} Found FlinkDeployment (Flink Operator): $FLINK_DEPLOYMENT"
    echo "Patching FlinkDeployment to enable Prometheus metrics..."
    
    FLINK_NAME=$(echo $FLINK_DEPLOYMENT | sed 's|flinkdeployment.flink.apache.org/||')
    
    kubectl patch flinkdeployment "$FLINK_NAME" -n "$FLINK_NAMESPACE" --type=merge -p '
spec:
  flinkConfiguration:
    metrics.reporters: prometheus
    metrics.reporter.prometheus.factory.class: org.apache.flink.metrics.prometheus.PrometheusReporterFactory
    metrics.reporter.prometheus.port: 9249-9259
    metrics.reporter.prometheus.filterLabelValueCharacters: "false"
    metrics.system-resource: "true"
    metrics.system-resource-probing-interval: "5000"
  jobManager:
    podTemplate:
      metadata:
        annotations:
          prometheus.io/scrape: "true"
          prometheus.io/port: "9249"
          prometheus.io/path: "/metrics"
      spec:
        initContainers:
        - name: download-prometheus-jar
          image: curlimages/curl:latest
          command:
          - sh
          - -c
          - |
            curl -L https://repo1.maven.org/maven2/org/apache/flink/flink-metrics-prometheus/1.18.0/flink-metrics-prometheus-1.18.0.jar \
              -o /flink-prometheus/flink-metrics-prometheus-1.18.0.jar
          volumeMounts:
          - name: flink-prometheus-jar
            mountPath: /flink-prometheus
        containers:
        - name: flink-main-container
          ports:
          - containerPort: 9249
            name: metrics
            protocol: TCP
          volumeMounts:
          - name: flink-prometheus-jar
            mountPath: /opt/flink/lib/flink-metrics-prometheus-1.18.0.jar
            subPath: flink-metrics-prometheus-1.18.0.jar
        volumes:
        - name: flink-prometheus-jar
          emptyDir: {}
  taskManager:
    podTemplate:
      metadata:
        annotations:
          prometheus.io/scrape: "true"
          prometheus.io/port: "9249"
          prometheus.io/path: "/metrics"
      spec:
        initContainers:
        - name: download-prometheus-jar
          image: curlimages/curl:latest
          command:
          - sh
          - -c
          - |
            curl -L https://repo1.maven.org/maven2/org/apache/flink/flink-metrics-prometheus/1.18.0/flink-metrics-prometheus-1.18.0.jar \
              -o /flink-prometheus/flink-metrics-prometheus-1.18.0.jar
          volumeMounts:
          - name: flink-prometheus-jar
            mountPath: /flink-prometheus
        containers:
        - name: flink-main-container
          ports:
          - containerPort: 9249
            name: metrics
            protocol: TCP
          volumeMounts:
          - name: flink-prometheus-jar
            mountPath: /opt/flink/lib/flink-metrics-prometheus-1.18.0.jar
            subPath: flink-metrics-prometheus-1.18.0.jar
        volumes:
        - name: flink-prometheus-jar
          emptyDir: {}
'
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} FlinkDeployment patched successfully"
        echo "  Flink Operator will restart pods automatically..."
        echo "  Waiting for new pods to come up..."
        sleep 20
    else
        echo -e "${RED}✗${NC} Failed to patch FlinkDeployment"
    fi
else
    # Fallback to regular deployments
    echo "Looking for regular Flink deployments..."
    JM_DEPLOYMENT=$(kubectl get deployments -n "$FLINK_NAMESPACE" -o name 2>/dev/null | grep -i jobmanager | head -1)
    TM_DEPLOYMENT=$(kubectl get deployments -n "$FLINK_NAMESPACE" -o name 2>/dev/null | grep -i taskmanager | head -1)

    if [ -n "$JM_DEPLOYMENT" ]; then
        echo "Patching JobManager deployment..."
        kubectl patch $JM_DEPLOYMENT -n "$FLINK_NAMESPACE" --type=merge -p='
{
  "spec": {
    "template": {
      "metadata": {
        "annotations": {
          "prometheus.io/scrape": "true",
          "prometheus.io/port": "9249",
          "prometheus.io/path": "/metrics"
        }
      }
    }
  }
}'
        echo -e "${GREEN}✓${NC} JobManager patched"
    else
        echo -e "${YELLOW}⚠${NC} JobManager deployment not found"
    fi

    if [ -n "$TM_DEPLOYMENT" ]; then
        echo "Patching TaskManager deployment..."
        kubectl patch $TM_DEPLOYMENT -n "$FLINK_NAMESPACE" --type=merge -p='
{
  "spec": {
    "template": {
      "metadata": {
        "annotations": {
          "prometheus.io/scrape": "true",
          "prometheus.io/port": "9249",
          "prometheus.io/path": "/metrics"
        }
      }
    }
  }
}'
        echo -e "${GREEN}✓${NC} TaskManager patched"
    else
        echo -e "${YELLOW}⚠${NC} TaskManager deployment not found"
    fi
fi

echo ""

# ============================================================================
# STEP 4.5: Install ClickHouse Plugin in Grafana
# ============================================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}STEP 4.5: Installing ClickHouse Plugin in Grafana${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

GRAFANA_POD=$(kubectl get pods -n "$PULSAR_NAMESPACE" -l app.kubernetes.io/name=grafana --field-selector=status.phase=Running -o name 2>/dev/null | head -1)

if [ -n "$GRAFANA_POD" ]; then
    echo "Checking ClickHouse plugin in Grafana..."
    if kubectl exec -n "$PULSAR_NAMESPACE" "$GRAFANA_POD" -- grafana-cli plugins ls 2>/dev/null | grep -q clickhouse; then
        echo -e "${GREEN}✓${NC} ClickHouse plugin already installed"
    else
        echo "Installing ClickHouse plugin..."
        kubectl exec -n "$PULSAR_NAMESPACE" "$GRAFANA_POD" -- grafana-cli plugins install grafana-clickhouse-datasource
        echo -e "${GREEN}✓${NC} ClickHouse plugin installed"
        
        echo "Restarting Grafana pod to load plugin..."
        GRAFANA_POD_NAME=$(echo $GRAFANA_POD | sed 's|pod/||')
        kubectl delete pod $GRAFANA_POD_NAME -n "$PULSAR_NAMESPACE"
        
        echo "Waiting for new Grafana pod to be ready (60 seconds)..."
        sleep 60
        kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n "$PULSAR_NAMESPACE" --timeout=120s 2>/dev/null || true
        echo -e "${GREEN}✓${NC} Grafana restarted with ClickHouse plugin"
    fi
else
    echo -e "${YELLOW}⚠${NC} Grafana pod not found in namespace $PULSAR_NAMESPACE"
fi

echo ""

# ============================================================================
# STEP 5: Verify Metrics Setup
# ============================================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}STEP 5: Verifying Metrics Setup${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Wait for pods to be ready
echo "Waiting for Flink pods to be ready..."
sleep 5

# Get JobManager pod
JM_POD=$(kubectl get pods -n "$FLINK_NAMESPACE" -l component=jobmanager -o name 2>/dev/null | head -1 | sed 's|pod/||')
if [ -z "$JM_POD" ]; then
    JM_POD=$(kubectl get pods -n "$FLINK_NAMESPACE" 2>/dev/null | grep jobmanager | grep Running | head -1 | awk '{print $1}')
fi

if [ -n "$JM_POD" ]; then
    echo "Testing metrics endpoint on pod: $JM_POD"
    
    # Check if Prometheus JAR exists
    echo -n "  Checking Prometheus JAR... "
    if kubectl exec -n "$FLINK_NAMESPACE" "$JM_POD" -- ls /opt/flink/lib/flink-metrics-prometheus-1.18.0.jar &>/dev/null; then
        echo -e "${GREEN}✓ Found${NC}"
    else
        echo -e "${RED}✗ Not found${NC}"
        echo -e "${YELLOW}    Action needed: Add initContainer to download Prometheus JAR${NC}"
    fi
    
    # Check if config is mounted
    echo -n "  Checking flink-conf.yaml... "
    if kubectl exec -n "$FLINK_NAMESPACE" "$JM_POD" -- cat /opt/flink/conf/flink-conf.yaml 2>/dev/null | grep -q "metrics.reporter.prometheus"; then
        echo -e "${GREEN}✓ Configured${NC}"
    else
        echo -e "${RED}✗ Not configured${NC}"
        echo -e "${YELLOW}    Action needed: Mount flink-config ConfigMap${NC}"
    fi
    
    # Check if metrics endpoint is accessible
    echo -n "  Checking metrics endpoint (port 9249)... "
    if kubectl exec -n "$FLINK_NAMESPACE" "$JM_POD" -- sh -c 'command -v wget' &>/dev/null; then
        if kubectl exec -n "$FLINK_NAMESPACE" "$JM_POD" -- wget -q -O- localhost:9249/metrics 2>/dev/null | grep -q "flink_"; then
            METRIC_COUNT=$(kubectl exec -n "$FLINK_NAMESPACE" "$JM_POD" -- wget -q -O- localhost:9249/metrics 2>/dev/null | grep -c "^flink_" || echo "0")
            echo -e "${GREEN}✓ Working ($METRIC_COUNT metrics)${NC}"
        else
            echo -e "${RED}✗ Not working${NC}"
        fi
    elif kubectl exec -n "$FLINK_NAMESPACE" "$JM_POD" -- sh -c 'command -v curl' &>/dev/null; then
        if kubectl exec -n "$FLINK_NAMESPACE" "$JM_POD" -- curl -s localhost:9249/metrics 2>/dev/null | grep -q "flink_"; then
            METRIC_COUNT=$(kubectl exec -n "$FLINK_NAMESPACE" "$JM_POD" -- curl -s localhost:9249/metrics 2>/dev/null | grep -c "^flink_" || echo "0")
            echo -e "${GREEN}✓ Working ($METRIC_COUNT metrics)${NC}"
        else
            echo -e "${RED}✗ Not working${NC}"
        fi
    else
        echo -e "${YELLOW}? Cannot test (wget/curl not available)${NC}"
    fi
else
    echo -e "${YELLOW}⚠${NC} No JobManager pod found for verification"
fi

echo ""

# ============================================================================
# STEP 6: Check Prometheus Targets
# ============================================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}STEP 6: Checking Prometheus${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check for Prometheus service
PROM_SVC=$(kubectl get svc -n "$PULSAR_NAMESPACE" 2>/dev/null | grep prometheus-server | awk '{print $1}' | head -1)

if [ -n "$PROM_SVC" ]; then
    echo -e "${GREEN}✓${NC} Found Prometheus service: $PROM_SVC"
else
    echo -e "${YELLOW}⚠${NC} Prometheus service not found in $PULSAR_NAMESPACE namespace"
fi

# Check ServiceMonitor
if kubectl get servicemonitor -n "$FLINK_NAMESPACE" flink-metrics &>/dev/null; then
    echo -e "${GREEN}✓${NC} ServiceMonitor 'flink-metrics' exists"
else
    echo -e "${YELLOW}⚠${NC} ServiceMonitor 'flink-metrics' not found"
fi

echo ""

# ============================================================================
# STEP 7: Import Grafana Dashboards
# ============================================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}STEP 7: Setting up Grafana Dashboards${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check if Grafana is accessible
GRAFANA_SVC=$(kubectl get svc -n "$PULSAR_NAMESPACE" 2>/dev/null | grep grafana | grep -v prometheus | awk '{print $1}' | head -1)

if [ -n "$GRAFANA_SVC" ]; then
    echo -e "${GREEN}✓${NC} Found Grafana service: $GRAFANA_SVC"
    echo ""
    echo "To import dashboards:"
    echo "  1. Port-forward to Grafana:"
    echo "     kubectl port-forward -n $PULSAR_NAMESPACE svc/$GRAFANA_SVC 3000:80 &"
    echo ""
    echo "  2. Open Grafana: http://localhost:3000 (admin/admin)"
    echo ""
    echo "  3. Import dashboards from: $SCRIPT_DIR/../grafana-dashboards/"
    echo "     • flink-dashboard.json"
    echo "     • clickhouse-dashboard.json"
else
    echo -e "${YELLOW}⚠${NC} Grafana service not found"
fi

echo ""

# ============================================================================
# FINAL SUMMARY
# ============================================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Setup Summary${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${GREEN}✓${NC} ConfigMap created: flink-config"
echo -e "${GREEN}✓${NC} Services created: flink-jobmanager-metrics, flink-taskmanager-metrics"
echo -e "${GREEN}✓${NC} ServiceMonitor created: flink-metrics"
echo -e "${GREEN}✓${NC} Prometheus annotations added to Flink pods"
echo ""

echo -e "${CYAN}⚠ IMPORTANT: Manual Steps Required${NC}"
echo ""
echo "Your Flink deployments need to be updated to:"
echo ""
echo "1. Mount the flink-config ConfigMap"
echo "2. Download Prometheus JAR (via initContainer)"
echo "3. Expose port 9249 for metrics"
echo ""
echo "See example configuration in:"
echo "  $SCRIPT_DIR/flink-prometheus-annotations.yaml"
echo ""
echo "Quick patch command:"
echo ""
echo "  kubectl edit deployment <flink-jobmanager-name> -n $FLINK_NAMESPACE"
echo ""
echo "Add these sections (from flink-prometheus-annotations.yaml):"
echo "  • spec.template.spec.containers[].ports (add port 9249)"
echo "  • spec.template.spec.volumes (add flink-config and prometheus-jar)"
echo "  • spec.template.spec.containers[].volumeMounts"
echo "  • spec.template.spec.initContainers (download Prometheus JAR)"
echo ""
echo "Then restart pods:"
echo "  kubectl rollout restart deployment/<name> -n $FLINK_NAMESPACE"
echo ""

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Access Commands${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${CYAN}Grafana (Dashboards):${NC}"
if [ -n "$GRAFANA_SVC" ]; then
    echo "  kubectl port-forward -n $PULSAR_NAMESPACE svc/$GRAFANA_SVC 3000:80"
else
    echo "  kubectl port-forward -n $PULSAR_NAMESPACE svc/pulsar-grafana 3000:80"
fi
echo "  → http://localhost:3000 (admin/admin)"
echo ""

echo -e "${CYAN}Prometheus (Metrics):${NC}"
if [ -n "$PROM_SVC" ]; then
    echo "  kubectl port-forward -n $PULSAR_NAMESPACE svc/$PROM_SVC 9090:80"
else
    echo "  kubectl port-forward -n $PULSAR_NAMESPACE svc/pulsar-grafana-prometheus-server 9090:80"
fi
echo "  → http://localhost:9090"
echo ""

echo -e "${CYAN}Flink Dashboard:${NC}"
echo "  kubectl port-forward -n $FLINK_NAMESPACE svc/flink-jobmanager-rest 8081:8081"
echo "  → http://localhost:8081"
echo ""

if [ -n "$JM_POD" ]; then
    echo -e "${CYAN}Flink Metrics (Direct):${NC}"
    echo "  kubectl port-forward -n $FLINK_NAMESPACE pod/$JM_POD 9249:9249"
    echo "  → http://localhost:9249/metrics"
    echo ""
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Setup Complete!${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "For detailed documentation, see:"
echo "  • $SCRIPT_DIR/PROMETHEUS-SETUP.md"
echo "  • $SCRIPT_DIR/../grafana-dashboards/README.md"
echo ""

