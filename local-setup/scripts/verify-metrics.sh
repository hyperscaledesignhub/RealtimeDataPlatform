#!/bin/bash

# Verify Flink Metrics Setup
# ===========================

echo "🔍 Verifying Flink Metrics Setup..."
echo "===================================="
echo ""

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_service() {
    local service=$1
    local port=$2
    local name=$3
    
    if curl -s -f "http://localhost:$port" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} $name is accessible at http://localhost:$port"
        return 0
    else
        echo -e "${RED}✗${NC} $name is NOT accessible at http://localhost:$port"
        return 1
    fi
}

check_container() {
    local container=$1
    
    if docker ps --filter "name=$container" --filter "status=running" | grep -q "$container"; then
        echo -e "${GREEN}✓${NC} Container $container is running"
        return 0
    else
        echo -e "${RED}✗${NC} Container $container is NOT running"
        return 1
    fi
}

check_metrics() {
    local endpoint=$1
    local name=$2
    
    if curl -s "$endpoint" | grep -q "flink"; then
        echo -e "${GREEN}✓${NC} $name metrics are available"
        local count=$(curl -s "$endpoint" | grep "flink_" | wc -l)
        echo "  Found $count Flink metrics"
        return 0
    else
        echo -e "${RED}✗${NC} $name metrics are NOT available"
        return 1
    fi
}

check_prometheus_target() {
    local target=$1
    
    if curl -s "http://localhost:9090/api/v1/targets" | grep -q "\"instance\":\"$target\"" | grep -q "\"health\":\"up\""; then
        echo -e "${GREEN}✓${NC} Prometheus is scraping $target"
        return 0
    else
        echo -e "${YELLOW}⚠${NC} Prometheus may not be scraping $target correctly"
        return 1
    fi
}

# Check Docker containers
echo "1. Checking Docker Containers..."
echo "--------------------------------"
check_container "flink-jobmanager"
check_container "flink-taskmanager-1"
check_container "prometheus"
check_container "grafana"
check_container "pulsar-standalone"
check_container "clickhouse"
check_container "iot-producer"
echo ""

# Check services accessibility
echo "2. Checking Service Endpoints..."
echo "--------------------------------"
check_service "localhost" "8081" "Flink Dashboard"
check_service "localhost" "9090" "Prometheus"
check_service "localhost" "3000" "Grafana"
check_service "localhost" "8080" "Pulsar Admin"
check_service "localhost" "8123" "ClickHouse HTTP"
echo ""

# Check Flink metrics endpoints
echo "3. Checking Flink Metrics Endpoints..."
echo "---------------------------------------"
check_metrics "http://localhost:9249/metrics" "Flink JobManager"
check_metrics "http://localhost:9250/metrics" "Flink TaskManager"
echo ""

# Check Pulsar metrics endpoints
echo "3a. Checking Pulsar Metrics Endpoints..."
echo "-----------------------------------------"
if curl -s "http://localhost:8080/metrics" > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Pulsar metrics endpoint is accessible"
    pulsar_count=$(curl -s "http://localhost:8080/metrics" | grep "pulsar_" | wc -l)
    echo "  Found $pulsar_count Pulsar metrics"
else
    echo -e "${RED}✗${NC} Pulsar metrics endpoint is NOT accessible"
fi
echo ""

# Check Prometheus targets
echo "4. Checking Prometheus Configuration..."
echo "----------------------------------------"
if curl -s "http://localhost:9090/api/v1/targets" > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Prometheus API is accessible"
    
    # Check if Flink targets are configured
    if curl -s "http://localhost:9090/api/v1/targets" | grep -q "flink"; then
        echo -e "${GREEN}✓${NC} Flink targets are configured in Prometheus"
    else
        echo -e "${RED}✗${NC} Flink targets are NOT configured in Prometheus"
    fi
else
    echo -e "${RED}✗${NC} Prometheus API is not accessible"
fi
echo ""

# Check Grafana datasources
echo "5. Checking Grafana Configuration..."
echo "-------------------------------------"
if curl -s -u admin:admin "http://localhost:3000/api/datasources" > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Grafana API is accessible"
    
    # Check for Prometheus datasource
    if curl -s -u admin:admin "http://localhost:3000/api/datasources" | grep -q "Prometheus"; then
        echo -e "${GREEN}✓${NC} Prometheus datasource is configured in Grafana"
    else
        echo -e "${YELLOW}⚠${NC} Prometheus datasource may not be configured in Grafana"
    fi
    
    # Check for ClickHouse datasource
    if curl -s -u admin:admin "http://localhost:3000/api/datasources" | grep -q "ClickHouse"; then
        echo -e "${GREEN}✓${NC} ClickHouse datasource is configured in Grafana"
    else
        echo -e "${YELLOW}⚠${NC} ClickHouse datasource may not be configured in Grafana"
    fi
else
    echo -e "${YELLOW}⚠${NC} Grafana API is not accessible (may still be starting up)"
fi
echo ""

# Check Flink jobs
echo "6. Checking Flink Jobs..."
echo "-------------------------"
if docker exec flink-jobmanager /opt/flink/bin/flink list 2>/dev/null | grep -q "RUNNING"; then
    echo -e "${GREEN}✓${NC} Flink job is running"
    docker exec flink-jobmanager /opt/flink/bin/flink list 2>/dev/null | grep "RUNNING"
else
    echo -e "${YELLOW}⚠${NC} No Flink jobs are currently running"
fi
echo ""

# Check if metrics are being collected
echo "7. Testing Metrics Collection..."
echo "--------------------------------"
sleep 5  # Wait a bit for metrics to be scraped

# Check if Prometheus has Flink metrics
if curl -s "http://localhost:9090/api/v1/query?query=up{job='flink-jobmanager'}" | grep -q '"value":\['; then
    echo -e "${GREEN}✓${NC} Prometheus is collecting Flink JobManager metrics"
else
    echo -e "${YELLOW}⚠${NC} Prometheus may not be collecting Flink JobManager metrics yet (wait 15-30 seconds)"
fi

if curl -s "http://localhost:9090/api/v1/query?query=up{job='flink-taskmanager'}" | grep -q '"value":\['; then
    echo -e "${GREEN}✓${NC} Prometheus is collecting Flink TaskManager metrics"
else
    echo -e "${YELLOW}⚠${NC} Prometheus may not be collecting Flink TaskManager metrics yet (wait 15-30 seconds)"
fi

if curl -s "http://localhost:9090/api/v1/query?query=up{job='pulsar'}" | grep -q '"value":\['; then
    echo -e "${GREEN}✓${NC} Prometheus is collecting Pulsar metrics"
else
    echo -e "${YELLOW}⚠${NC} Prometheus may not be collecting Pulsar metrics yet (wait 15-30 seconds)"
fi
echo ""

# Summary
echo "=================================="
echo "📊 Verification Complete!"
echo "=================================="
echo ""
echo "Access Points:"
echo "  • Grafana Dashboard: http://localhost:3000 (admin/admin)"
echo "  • Flink Dashboard: http://localhost:8081"
echo "  • Prometheus: http://localhost:9090"
echo ""
echo "Next Steps:"
echo "  1. Open Grafana at http://localhost:3000"
echo "  2. Login with admin/admin"
echo "  3. Go to Dashboards to view:"
echo "     - Flink IoT Pipeline Metrics"
echo "     - Pulsar Metrics"
echo "     - ClickHouse Metrics"
echo "  4. View real-time metrics from all services"
echo ""
echo "For troubleshooting, see: FLINK-METRICS-GUIDE.md"
echo ""

