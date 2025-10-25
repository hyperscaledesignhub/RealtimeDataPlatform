#!/bin/bash

# Import Grafana Dashboards to Kubernetes Grafana
# ================================================

set -e

PULSAR_NAMESPACE="pulsar"
GRAFANA_URL="http://localhost:3000"
GRAFANA_USER="admin"
GRAFANA_PASS="admin123"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🎨 Importing Grafana Dashboards for Flink Metrics"
echo "=================================================="
echo ""

echo "Step 1: Starting port-forward to Grafana..."
kubectl port-forward -n $PULSAR_NAMESPACE svc/pulsar-grafana 3000:80 > /tmp/grafana-forward.log 2>&1 &
PF_PID=$!
echo "✓ Port-forward started (PID: $PF_PID)"
sleep 5

echo ""
echo "Step 2: Testing Grafana connection..."
if curl -s "$GRAFANA_URL/api/health" > /dev/null 2>&1; then
    echo "✓ Grafana is accessible"
else
    echo "✗ Grafana is not accessible at $GRAFANA_URL"
    echo "  Waiting a bit longer..."
    sleep 5
    if curl -s "$GRAFANA_URL/api/health" > /dev/null 2>&1; then
        echo "✓ Grafana is now accessible"
    else
        echo "✗ Still not accessible. Please check port-forward manually"
        kill $PF_PID 2>/dev/null
        exit 1
    fi
fi

echo ""
echo "Step 2.5: Installing ClickHouse Plugin..."
echo "Checking if ClickHouse plugin is installed..."
kubectl exec -n $PULSAR_NAMESPACE deployment/pulsar-grafana -- grafana-cli plugins ls 2>/dev/null | grep -q clickhouse
if [ $? -eq 0 ]; then
    echo "✓ ClickHouse plugin already installed"
else
    echo "Installing ClickHouse plugin..."
    kubectl exec -n $PULSAR_NAMESPACE deployment/pulsar-grafana -- grafana-cli plugins install grafana-clickhouse-datasource
    echo "✓ Plugin installed"
    echo "Restarting Grafana to load plugin..."
    kubectl rollout restart deployment/pulsar-grafana -n $PULSAR_NAMESPACE
    
    # Wait for Grafana to restart
    echo "Waiting for Grafana to restart (30 seconds)..."
    sleep 30
    
    # Restart port-forward
    kill $PF_PID 2>/dev/null
    kubectl port-forward -n $PULSAR_NAMESPACE svc/pulsar-grafana 3000:80 > /tmp/grafana-forward.log 2>&1 &
    PF_PID=$!
    sleep 5
    echo "✓ Grafana restarted and ready"
fi

echo ""
echo "Step 3: Checking/Creating Datasources..."

# Check if Prometheus datasource exists
PROM_DS=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASS" "$GRAFANA_URL/api/datasources/uid/prometheus" 2>/dev/null)

if echo "$PROM_DS" | grep -q '"uid":"prometheus"'; then
    echo "✓ Prometheus datasource already exists"
else
    echo "Creating Prometheus datasource..."
    curl -X POST -H "Content-Type: application/json" -u "$GRAFANA_USER:$GRAFANA_PASS" \
      "$GRAFANA_URL/api/datasources" -d '{
        "name": "Prometheus",
        "type": "prometheus",
        "uid": "prometheus",
        "url": "http://vmsingle-pulsar-victoria-metrics-k8s-stack.pulsar.svc.cluster.local:8429",
        "access": "proxy",
        "isDefault": true,
        "jsonData": {
          "timeInterval": "5s",
          "queryTimeout": "300s",
          "httpMethod": "POST"
        }
      }' 2>&1 | grep -q "success\|Datasource added" && echo "✓ Prometheus datasource created" || echo "⚠ May already exist"
fi

# Check if ClickHouse datasource exists
CH_DS=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASS" "$GRAFANA_URL/api/datasources/uid/clickhouse" 2>/dev/null)

if echo "$CH_DS" | grep -q '"uid":"clickhouse"'; then
    echo "✓ ClickHouse datasource already exists"
else
    echo "Creating ClickHouse datasource..."
    curl -X POST -H "Content-Type: application/json" -u "$GRAFANA_USER:$GRAFANA_PASS" \
      "$GRAFANA_URL/api/datasources" -d '{
        "name": "ClickHouse",
        "type": "grafana-clickhouse-datasource",
        "uid": "clickhouse",
        "url": "http://clickhouse-iot-cluster-repl.clickhouse.svc.cluster.local:8123",
        "access": "proxy",
        "database": "benchmark",
        "jsonData": {
          "defaultDatabase": "benchmark",
          "port": 8123,
          "server": "clickhouse-iot-cluster-repl.clickhouse.svc.cluster.local",
          "protocol": "http",
          "username": "default"
        }
      }' 2>&1 | grep -q "success\|Datasource added" && echo "✓ ClickHouse datasource created" || echo "⚠ May already exist"
fi

echo ""
echo "Step 4: Preparing Dashboards..."

# Update ClickHouse dashboard to use distributed table
echo "Updating ClickHouse dashboard to use distributed table..."
sed 's/benchmark\.sensors_local/benchmark.sensors_distributed/g' "$SCRIPT_DIR/clickhouse-dashboard.json" > /tmp/clickhouse-dashboard-fixed.json
echo "✓ Dashboard configured for distributed table"

echo ""
echo "Step 5: Importing Dashboards..."

# Import Flink dashboard
echo "Importing Flink Metrics Dashboard..."
cat "$SCRIPT_DIR/flink-dashboard.json" | jq '{dashboard: ., overwrite: true, message: "Flink Metrics Dashboard"}' > /tmp/flink-dashboard-import.json
curl -X POST -H "Content-Type: application/json" -u "$GRAFANA_USER:$GRAFANA_PASS" \
  "$GRAFANA_URL/api/dashboards/db" -d @/tmp/flink-dashboard-import.json 2>&1 | \
  grep -o '"url":"[^"]*"' | sed 's/"url":"/  URL: http:\/\/localhost:3000/' | sed 's/"$//'
echo "✓ Flink dashboard imported"

# Import ClickHouse dashboard
echo ""
echo "Importing ClickHouse Data Dashboard..."
cat "/tmp/clickhouse-dashboard-fixed.json" | jq '{dashboard: ., overwrite: true, message: "ClickHouse Data Dashboard"}' > /tmp/clickhouse-dashboard-import.json
curl -X POST -H "Content-Type: application/json" -u "$GRAFANA_USER:$GRAFANA_PASS" \
  "$GRAFANA_URL/api/dashboards/db" -d @/tmp/clickhouse-dashboard-import.json 2>&1 | \
  grep -o '"url":"[^"]*"' | sed 's/"url":"/  URL: http:\/\/localhost:3000/' | sed 's/"$//'
echo "✓ ClickHouse dashboard imported"

# Cleanup
rm -f /tmp/flink-dashboard-import.json /tmp/clickhouse-dashboard-import.json /tmp/clickhouse-dashboard-fixed.json

echo ""
echo "=================================================="
echo "✅ Dashboards Imported Successfully!"
echo "=================================================="
echo ""
echo "📊 Access Your Dashboards:"
echo ""
echo "Flink Metrics Dashboard:"
echo "  http://localhost:3000/d/flink-iot-pipeline/flink-iot-pipeline-metrics"
echo ""
echo "ClickHouse Data Dashboard:"
echo "  http://localhost:3000/d/clickhouse-iot-metrics/clickhouse-iot-data-metrics"
echo ""
echo "Login: $GRAFANA_USER / $GRAFANA_PASS"
echo ""
echo "⚠ Port-forward is running in background (PID: $PF_PID)"
echo "  To stop it: kill $PF_PID"
echo ""
echo "Press Ctrl+C to stop, or keep this terminal open to maintain access"
echo ""

# Keep the script running to maintain port-forward
wait $PF_PID

