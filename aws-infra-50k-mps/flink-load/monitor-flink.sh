#!/bin/bash

# Flink Metrics Monitoring Setup and Verification Script
# =======================================================
# This script sets up Flink to send metrics to Prometheus and verifies the setup

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
FLINK_NAMESPACE="${FLINK_NAMESPACE:-flink-benchmark}"
PULSAR_NAMESPACE="${PULSAR_NAMESPACE:-pulsar}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Functions
print_header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl not found. Please install kubectl first."
        exit 1
    fi
    print_success "kubectl is installed"
}

check_namespace() {
    local ns=$1
    if ! kubectl get namespace "$ns" &> /dev/null; then
        print_warning "Namespace '$ns' not found"
        return 1
    fi
    print_success "Namespace '$ns' exists"
    return 0
}

setup_flink_config() {
    print_header "Setting up Flink Configuration"
    
    # Update namespace in ConfigMap
    sed "s/namespace: flink/namespace: $FLINK_NAMESPACE/g" "$SCRIPT_DIR/flink-config-configmap.yaml" > /tmp/flink-config-configmap.yaml
    
    echo "Creating Flink ConfigMap with Prometheus metrics configuration..."
    if kubectl apply -f /tmp/flink-config-configmap.yaml; then
        print_success "Flink ConfigMap created"
    else
        print_error "Failed to create Flink ConfigMap"
        return 1
    fi
    
    rm /tmp/flink-config-configmap.yaml
}

setup_servicemonitor() {
    print_header "Setting up ServiceMonitor for Prometheus"
    
    # Update namespace in ServiceMonitor
    sed "s/namespace: flink/namespace: $FLINK_NAMESPACE/g" "$SCRIPT_DIR/flink-servicemonitor.yaml" > /tmp/flink-servicemonitor.yaml
    
    echo "Creating Services and ServiceMonitor..."
    if kubectl apply -f /tmp/flink-servicemonitor.yaml; then
        print_success "ServiceMonitor and Services created"
    else
        print_warning "Failed to create ServiceMonitor (may not be using Prometheus Operator)"
    fi
    
    rm /tmp/flink-servicemonitor.yaml
}

check_flink_pods() {
    print_header "Checking Flink Pods"
    
    echo "Looking for Flink pods in namespace '$FLINK_NAMESPACE'..."
    
    JOBMANAGER_PODS=$(kubectl get pods -n "$FLINK_NAMESPACE" -l component=jobmanager -o name 2>/dev/null)
    TASKMANAGER_PODS=$(kubectl get pods -n "$FLINK_NAMESPACE" -l component=taskmanager -o name 2>/dev/null)
    
    if [ -z "$JOBMANAGER_PODS" ]; then
        print_warning "No JobManager pods found with label 'component=jobmanager'"
        echo "Trying alternative labels..."
        JOBMANAGER_PODS=$(kubectl get pods -n "$FLINK_NAMESPACE" | grep jobmanager | awk '{print "pod/" $1}')
    fi
    
    if [ -z "$TASKMANAGER_PODS" ]; then
        print_warning "No TaskManager pods found with label 'component=taskmanager'"
        echo "Trying alternative labels..."
        TASKMANAGER_PODS=$(kubectl get pods -n "$FLINK_NAMESPACE" | grep taskmanager | awk '{print "pod/" $1}')
    fi
    
    if [ -n "$JOBMANAGER_PODS" ]; then
        print_success "Found JobManager pods:"
        echo "$JOBMANAGER_PODS" | while read pod; do
            echo "  • $pod"
        done
    else
        print_error "No JobManager pods found"
        return 1
    fi
    
    if [ -n "$TASKMANAGER_PODS" ]; then
        print_success "Found TaskManager pods:"
        echo "$TASKMANAGER_PODS" | while read pod; do
            echo "  • $pod"
        done
    else
        print_warning "No TaskManager pods found"
    fi
}

verify_metrics_endpoint() {
    print_header "Verifying Flink Metrics Endpoint"
    
    # Get first JobManager pod
    JM_POD=$(kubectl get pods -n "$FLINK_NAMESPACE" -l component=jobmanager -o name 2>/dev/null | head -1)
    
    if [ -z "$JM_POD" ]; then
        JM_POD=$(kubectl get pods -n "$FLINK_NAMESPACE" | grep jobmanager | head -1 | awk '{print "pod/" $1}')
    fi
    
    if [ -z "$JM_POD" ]; then
        print_error "No JobManager pod found for testing"
        return 1
    fi
    
    echo "Testing metrics endpoint on $JM_POD..."
    
    if kubectl exec -n "$FLINK_NAMESPACE" "$JM_POD" -- wget -q -O- localhost:9249/metrics 2>/dev/null | grep -q "flink_"; then
        print_success "Metrics endpoint is working and exposing Flink metrics"
        
        # Count metrics
        METRIC_COUNT=$(kubectl exec -n "$FLINK_NAMESPACE" "$JM_POD" -- wget -q -O- localhost:9249/metrics 2>/dev/null | grep "^flink_" | wc -l)
        print_info "Found $METRIC_COUNT Flink metrics exposed"
    else
        print_error "Metrics endpoint not accessible or not exposing Flink metrics"
        print_warning "You may need to:"
        echo "  1. Ensure flink-conf.yaml is mounted in the pod"
        echo "  2. Ensure Prometheus JAR is in /opt/flink/lib/"
        echo "  3. Restart Flink pods to load the configuration"
        return 1
    fi
}

check_prometheus() {
    print_header "Checking Prometheus Configuration"
    
    echo "Looking for Prometheus in namespace '$PULSAR_NAMESPACE'..."
    
    PROM_SERVICE=$(kubectl get svc -n "$PULSAR_NAMESPACE" 2>/dev/null | grep prometheus-server | awk '{print $1}' | head -1)
    
    if [ -z "$PROM_SERVICE" ]; then
        print_warning "Prometheus service not found in namespace '$PULSAR_NAMESPACE'"
        print_info "Checking for Prometheus in other namespaces..."
        PROM_SERVICE=$(kubectl get svc --all-namespaces 2>/dev/null | grep prometheus-server | head -1 | awk '{print $1 "/" $2}')
        if [ -n "$PROM_SERVICE" ]; then
            print_success "Found Prometheus: $PROM_SERVICE"
        else
            print_error "Prometheus not found in cluster"
            return 1
        fi
    else
        print_success "Found Prometheus service: $PROM_SERVICE"
    fi
}

show_port_forward_commands() {
    print_header "Port Forward Commands"
    
    echo "Use these commands to access the monitoring stack:"
    echo ""
    
    # Grafana
    echo -e "${GREEN}📊 Grafana (for dashboards):${NC}"
    echo "   kubectl port-forward -n $PULSAR_NAMESPACE svc/pulsar-grafana 3000:80"
    echo "   URL: http://localhost:3000"
    echo "   Credentials: admin/admin"
    echo ""
    
    # Prometheus
    echo -e "${GREEN}📈 Prometheus (for metrics):${NC}"
    PROM_SVC=$(kubectl get svc -n "$PULSAR_NAMESPACE" 2>/dev/null | grep prometheus-server | awk '{print $1}' | head -1)
    if [ -n "$PROM_SVC" ]; then
        echo "   kubectl port-forward -n $PULSAR_NAMESPACE svc/$PROM_SVC 9090:80"
    else
        echo "   kubectl port-forward -n $PULSAR_NAMESPACE svc/pulsar-grafana-prometheus-server 9090:80"
    fi
    echo "   URL: http://localhost:9090"
    echo ""
    
    # Flink Dashboard
    echo -e "${GREEN}🔄 Flink Dashboard:${NC}"
    echo "   kubectl port-forward -n $FLINK_NAMESPACE svc/flink-jobmanager-rest 8081:8081"
    echo "   URL: http://localhost:8081"
    echo ""
    
    # Flink Metrics Direct
    JM_POD=$(kubectl get pods -n "$FLINK_NAMESPACE" -l component=jobmanager -o name 2>/dev/null | head -1 | sed 's|pod/||')
    if [ -z "$JM_POD" ]; then
        JM_POD=$(kubectl get pods -n "$FLINK_NAMESPACE" | grep jobmanager | head -1 | awk '{print $1}')
    fi
    
    if [ -n "$JM_POD" ]; then
        echo -e "${GREEN}🔍 Flink Metrics (direct):${NC}"
        echo "   kubectl port-forward -n $FLINK_NAMESPACE pod/$JM_POD 9249:9249"
        echo "   URL: http://localhost:9249/metrics"
        echo ""
    fi
}

show_next_steps() {
    print_header "Next Steps"
    
    echo "1. Update your Flink deployments to include:"
    echo "   • Mount the flink-config ConfigMap"
    echo "   • Add initContainer to download Prometheus JAR"
    echo "   • Expose port 9249 for metrics"
    echo "   • Add Prometheus annotations"
    echo ""
    echo "   See: flink-prometheus-annotations.yaml for complete examples"
    echo ""
    
    echo "2. Restart Flink pods to apply configuration:"
    echo "   kubectl rollout restart deployment/flink-jobmanager -n $FLINK_NAMESPACE"
    echo "   kubectl rollout restart deployment/flink-taskmanager -n $FLINK_NAMESPACE"
    echo ""
    
    echo "3. Verify metrics are being scraped by Prometheus:"
    echo "   kubectl port-forward -n $PULSAR_NAMESPACE svc/pulsar-grafana-prometheus-server 9090:80"
    echo "   Open: http://localhost:9090/targets (look for flink-metrics)"
    echo ""
    
    echo "4. Import Grafana dashboards:"
    echo "   kubectl port-forward -n $PULSAR_NAMESPACE svc/pulsar-grafana 3000:80"
    echo "   Open: http://localhost:3000"
    echo "   Import: ../grafana-dashboards/flink-dashboard.json"
    echo "   Import: ../grafana-dashboards/clickhouse-dashboard.json"
    echo ""
    
    echo "5. For detailed setup instructions, see:"
    echo "   PROMETHEUS-SETUP.md"
    echo ""
}

run_diagnostics() {
    print_header "Running Diagnostics"
    
    echo "Checking Flink pod configuration..."
    
    JM_POD=$(kubectl get pods -n "$FLINK_NAMESPACE" -l component=jobmanager -o name 2>/dev/null | head -1)
    if [ -z "$JM_POD" ]; then
        JM_POD=$(kubectl get pods -n "$FLINK_NAMESPACE" | grep jobmanager | head -1 | awk '{print "pod/" $1}')
    fi
    
    if [ -n "$JM_POD" ]; then
        echo ""
        echo "Checking if Prometheus JAR exists:"
        if kubectl exec -n "$FLINK_NAMESPACE" "$JM_POD" -- ls -la /opt/flink/lib/ 2>/dev/null | grep -q prometheus; then
            print_success "Prometheus JAR found in pod"
        else
            print_error "Prometheus JAR not found - needs to be downloaded"
        fi
        
        echo ""
        echo "Checking if flink-conf.yaml has metrics configuration:"
        if kubectl exec -n "$FLINK_NAMESPACE" "$JM_POD" -- cat /opt/flink/conf/flink-conf.yaml 2>/dev/null | grep -q "metrics.reporter.prometheus"; then
            print_success "Prometheus metrics reporter configured"
        else
            print_error "Prometheus metrics reporter not configured"
        fi
        
        echo ""
        echo "Checking if port 9249 is listening:"
        if kubectl exec -n "$FLINK_NAMESPACE" "$JM_POD" -- netstat -tuln 2>/dev/null | grep -q ":9249"; then
            print_success "Port 9249 is listening"
        else
            print_warning "Port 9249 is not listening (may need pod restart)"
        fi
    fi
}

# Main script execution
main() {
    clear
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║   Flink Metrics Monitoring Setup & Verification          ║"
    echo "║   For Kubernetes/AWS Deployment                          ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    print_info "Flink Namespace: $FLINK_NAMESPACE"
    print_info "Pulsar Namespace: $PULSAR_NAMESPACE"
    echo ""
    
    # Check prerequisites
    print_header "Checking Prerequisites"
    check_kubectl
    
    if ! check_namespace "$FLINK_NAMESPACE"; then
        print_error "Flink namespace not found. Please set FLINK_NAMESPACE environment variable."
        exit 1
    fi
    
    if ! check_namespace "$PULSAR_NAMESPACE"; then
        print_warning "Pulsar namespace not found. Metrics may not be collected."
    fi
    
    # Setup configuration
    setup_flink_config
    setup_servicemonitor
    
    # Verify setup
    check_flink_pods
    
    # Check if metrics are accessible
    if verify_metrics_endpoint; then
        print_success "Flink metrics are properly configured!"
    else
        print_warning "Flink metrics endpoint needs configuration"
        run_diagnostics
    fi
    
    # Check Prometheus
    check_prometheus
    
    # Show commands
    show_port_forward_commands
    
    # Show next steps
    show_next_steps
    
    print_header "Setup Complete"
    print_success "Configuration files have been applied"
    print_info "Follow the 'Next Steps' above to complete the setup"
    echo ""
}

# Parse command line arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --help, -h          Show this help message"
        echo "  --diagnostics, -d   Run diagnostics only"
        echo ""
        echo "Environment Variables:"
        echo "  FLINK_NAMESPACE     Kubernetes namespace where Flink is deployed (default: flink)"
        echo "  PULSAR_NAMESPACE    Kubernetes namespace where Pulsar/Prometheus is deployed (default: pulsar)"
        echo ""
        exit 0
        ;;
    --diagnostics|-d)
        check_kubectl
        check_flink_pods
        verify_metrics_endpoint
        run_diagnostics
        exit 0
        ;;
    *)
        main
        ;;
esac

