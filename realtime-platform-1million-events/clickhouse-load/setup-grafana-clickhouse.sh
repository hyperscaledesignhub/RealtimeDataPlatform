#!/bin/bash

# ================================================================================
# Setup Grafana with ClickHouse Data Source
# ================================================================================

set -e

echo "🎨 Setting up Grafana with ClickHouse Data Source"
echo "=================================================="

# Grafana configuration
GRAFANA_URL="http://localhost:3000"
GRAFANA_USER="admin"
GRAFANA_PASSWORD="admin"  # Default Pulsar Grafana password

# ClickHouse configuration
CLICKHOUSE_HOST="clickhouse-iot-cluster-repl.clickhouse.svc.cluster.local"
CLICKHOUSE_PORT="9000"
CLICKHOUSE_HTTP_PORT="8123"
CLICKHOUSE_USER="default"
CLICKHOUSE_PASSWORD=""

echo ""
echo "📊 Access Grafana at: $GRAFANA_URL"
echo "   Username: $GRAFANA_USER"
echo "   Password: $GRAFANA_PASSWORD"
echo ""

# Check if Grafana is accessible
echo "🔍 Checking Grafana connectivity..."
if ! curl -s "$GRAFANA_URL/api/health" > /dev/null; then
    echo "❌ Grafana is not accessible at $GRAFANA_URL"
    echo ""
    echo "Please run port-forward first:"
    echo "  kubectl port-forward -n pulsar svc/pulsar-grafana 3000:80"
    echo ""
    exit 1
fi

echo "✅ Grafana is accessible"
echo ""

# Install ClickHouse plugin
echo "📦 Installing ClickHouse data source plugin..."
kubectl exec -n pulsar deployment/pulsar-grafana -- grafana-cli plugins install grafana-clickhouse-datasource || echo "Plugin may already be installed"

echo ""
echo "🔄 Restarting Grafana to load plugin..."
kubectl rollout restart deployment/pulsar-grafana -n pulsar
sleep 10

echo ""
echo "✅ Setup instructions:"
echo ""
echo "1. Open Grafana: http://localhost:3000"
echo "   Login: admin / admin"
echo ""
echo "2. Add ClickHouse Data Source:"
echo "   - Go to: Configuration → Data Sources → Add data source"
echo "   - Search for: ClickHouse"
echo "   - Configure:"
echo "     Server Address: $CLICKHOUSE_HOST"
echo "     Server Port: $CLICKHOUSE_HTTP_PORT"
echo "     Protocol: http"
echo "     Username: $CLICKHOUSE_USER"
echo "     Password: (leave empty)"
echo "     Default Database: benchmark"
echo "   - Click 'Save & Test'"
echo ""
echo "3. Create Dashboard:"
echo "   - Click '+' → Dashboard"
echo "   - Add Panel"
echo "   - Select ClickHouse data source"
echo ""
echo "4. Example Queries:"
echo ""
echo "   a) Total Records:"
echo "      SELECT COUNT(*) FROM benchmark.sensors_distributed"
echo ""
echo "   b) Records per Shard:"
echo "      SELECT \$__timeInterval(time) as t, COUNT(*) as records"
echo "      FROM benchmark.sensors_distributed"
echo "      WHERE \$__timeFilter(time)"
echo "      GROUP BY t ORDER BY t"
echo ""
echo "   c) Temperature Over Time:"
echo "      SELECT \$__timeInterval(time) as t, avg(temperature) as avg_temp"
echo "      FROM benchmark.sensors_distributed"
echo "      WHERE \$__timeFilter(time)"
echo "      GROUP BY t ORDER BY t"
echo ""
echo "   d) Device Count:"
echo "      SELECT uniq(device_id) as unique_devices"
echo "      FROM benchmark.sensors_distributed"
echo ""
echo "   e) Alerts:"
echo "      SELECT \$__timeInterval(time) as t, SUM(has_alert) as alerts"
echo "      FROM benchmark.sensors_distributed"
echo "      WHERE \$__timeFilter(time)"
echo "      GROUP BY t ORDER BY t"
echo ""
echo "5. Import pre-built dashboards:"
echo "   - Dashboard ID 882 (ClickHouse Query Analysis)"
echo "   - Dashboard ID 14999 (ClickHouse Monitoring)"
echo ""
echo "=================================================="
echo "✅ Grafana setup complete!"
echo ""

