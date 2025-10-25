#!/bin/bash

# Port Forward Commands for AWS Deployment
# =========================================

echo "🔗 Setting up port forwards for monitoring stack..."
echo ""

# Function to check if port is already in use
check_port() {
    if lsof -Pi :$1 -sTCP:LISTEN -t >/dev/null ; then
        echo "⚠️  Port $1 is already in use. Kill the process or use a different port."
        return 1
    fi
    return 0
}

# 1. Grafana Port Forward
echo "📊 Grafana (UI):"
echo "   Command: kubectl port-forward -n pulsar svc/pulsar-grafana 3000:80"
echo "   URL: http://localhost:3000"
echo "   Credentials: admin/admin"
echo ""

# 2. Prometheus Port Forward (optional - for debugging)
echo "📈 Prometheus (metrics):"
echo "   Command: kubectl port-forward -n pulsar svc/pulsar-grafana-prometheus-server 9090:80"
echo "   URL: http://localhost:9090"
echo ""

# 3. ClickHouse Port Forward (optional - for direct queries)
echo "🗄️  ClickHouse (database):"
echo "   Command: kubectl port-forward -n clickhouse svc/clickhouse-iot-cluster-repl 8123:8123"
echo "   URL: http://localhost:8123"
echo ""

# 4. Flink Dashboard Port Forward
echo "🔄 Flink Dashboard:"
echo "   Command: kubectl port-forward -n <namespace> svc/flink-jobmanager-rest 8081:8081"
echo "   URL: http://localhost:8081"
echo "   Note: Replace <namespace> with your Flink namespace"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🚀 Quick Start Commands:"
echo ""
echo "# Start Grafana port-forward in background:"
echo "kubectl port-forward -n pulsar svc/pulsar-grafana 3000:80 &"
echo ""
echo "# Or run in separate terminal:"
echo "kubectl port-forward -n pulsar svc/pulsar-grafana 3000:80"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🔍 To find your actual service names, run:"
echo ""
echo "# List Grafana services:"
echo "kubectl get svc -n pulsar | grep grafana"
echo ""
echo "# List ClickHouse services:"
echo "kubectl get svc -n clickhouse"
echo ""
echo "# List all services in pulsar namespace:"
echo "kubectl get svc -n pulsar"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "💡 If service names are different, use this format:"
echo "   kubectl port-forward -n <namespace> svc/<service-name> <local-port>:<service-port>"
echo ""

