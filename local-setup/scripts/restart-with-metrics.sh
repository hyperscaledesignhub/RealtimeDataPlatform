#!/bin/bash

echo "🔄 RESTARTING PIPELINE WITH METRICS..."
echo "======================================"
echo ""

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

# Stop the pipeline
echo "🛑 Stopping current pipeline..."
bash scripts/stop-pipeline.sh

echo ""
echo "⏳ Waiting for cleanup..."
sleep 5

# Ensure Prometheus JAR is downloaded
echo "📦 Ensuring Flink Prometheus JAR is downloaded..."
FLINK_PROMETHEUS_JAR="flink-metrics-prometheus-1.18.0.jar"
if [ ! -f "/tmp/$FLINK_PROMETHEUS_JAR" ]; then
    echo "  → Downloading JAR..."
    curl -s -L "https://repo1.maven.org/maven2/org/apache/flink/flink-metrics-prometheus/1.18.0/$FLINK_PROMETHEUS_JAR" \
        -o "/tmp/$FLINK_PROMETHEUS_JAR"
else
    echo "  → JAR already exists"
fi

# Verify JAR size
JAR_SIZE=$(stat -f%z "/tmp/$FLINK_PROMETHEUS_JAR" 2>/dev/null || stat -c%s "/tmp/$FLINK_PROMETHEUS_JAR" 2>/dev/null)
if [ "$JAR_SIZE" -lt 50000 ]; then
    echo "  ⚠️  JAR seems too small, re-downloading..."
    rm -f "/tmp/$FLINK_PROMETHEUS_JAR"
    curl -s -L "https://repo1.maven.org/maven2/org/apache/flink/flink-metrics-prometheus/1.18.0/$FLINK_PROMETHEUS_JAR" \
        -o "/tmp/$FLINK_PROMETHEUS_JAR"
fi

echo "  ✓ JAR ready: $(ls -lh /tmp/$FLINK_PROMETHEUS_JAR | awk '{print $5}')"

echo ""
echo "🚀 Starting pipeline with metrics enabled..."
bash scripts/start-pipeline.sh

echo ""
echo "⏳ Waiting for services to fully initialize..."
sleep 10

echo ""
echo "🔍 Verifying metrics setup..."
echo ""

# Check JobManager metrics
if curl -s http://localhost:9249/metrics | grep -q "flink_"; then
    echo "✓ JobManager metrics are working!"
else
    echo "✗ JobManager metrics not yet available (may need more time)"
fi

# Check TaskManager metrics  
if curl -s http://localhost:9250/metrics | grep -q "flink_"; then
    echo "✓ TaskManager metrics are working!"
else
    echo "✗ TaskManager metrics not yet available (may need more time)"
fi

# Check Prometheus targets
if curl -s http://localhost:9090/api/v1/targets | grep -q "flink"; then
    echo "✓ Prometheus is configured to scrape Flink"
else
    echo "✗ Prometheus targets not yet configured"
fi

echo ""
echo "======================================"
echo "✅ RESTART COMPLETE!"
echo "======================================"
echo ""
echo "📊 Next Steps:"
echo "  1. Wait 30-60 seconds for metrics to be scraped"
echo "  2. Open Grafana: http://localhost:3000 (admin/admin)"
echo "  3. Go to Dashboards → Flink IoT Pipeline Metrics"
echo "  4. Refresh the dashboard to see metrics"
echo ""
echo "🔍 To verify metrics manually:"
echo "  • JobManager: curl http://localhost:9249/metrics"
echo "  • TaskManager: curl http://localhost:9250/metrics"
echo "  • Prometheus: http://localhost:9090/targets"
echo ""

