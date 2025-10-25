# 🚀 Quick Start Deployment Guide

## Complete Fresh Deployment Order

Follow these steps **in order** after a fresh install or complete cleanup:

### **Step 1: Deploy ClickHouse** ⏱️ ~3 minutes
```bash
cd clickhouse-load
./00-install-clickhouse.sh
```

**Wait for:** All ClickHouse pods to be Running
```bash
kubectl get pods -n clickhouse -w
```

---

### **Step 2: Create ClickHouse Schema on ALL Replicas** ⏱️ ~1 minute
```bash
cd clickhouse-load
./00-create-schema-all-replicas.sh
```

**✅ This script now:**
- Waits for all pods to be ready
- Creates tables on **every replica**
- Shows detailed verification table
- Reports exactly which replicas succeeded/failed

**Expected output:**
```
POD NAME                                          sensors_local        sensors_distributed
--------------------------------------------------------------------------------
chi-iot-cluster-repl-iot-cluster-1-0-0           ✓ EXISTS             ✓ EXISTS
chi-iot-cluster-repl-iot-cluster-1-1-0           ✓ EXISTS             ✓ EXISTS
chi-iot-cluster-repl-iot-cluster-1-1-1           ✓ EXISTS             ✓ EXISTS
```

---

### **Step 3: Deploy Flink** ⏱️ ~2 minutes
```bash
cd flink-load
./deploy.sh     # Deploys Flink Operator

kubectl apply -f flink-job-deployment.yaml -n flink-benchmark
```

**Wait for:** Flink JobManager and TaskManager pods
```bash
kubectl get pods -n flink-benchmark -w
```

---

### **Step 4: Setup Flink Metrics & Grafana Dashboards** ⏱️ ~2 minutes
```bash
cd flink-load
./setup-flink-metrics.sh
```

**This script automatically:**
- ✅ Patches FlinkDeployment with Prometheus metrics config
- ✅ Creates VMPodScrape for Victoria Metrics
- ✅ Installs ClickHouse plugin in Grafana
- ✅ Imports Flink + ClickHouse dashboards
- ✅ Restarts Grafana pod if needed

---

### **Step 5: Verify Everything is Working** ⏱️ ~1 minute

#### Check Flink is processing:
```bash
kubectl logs -n flink-benchmark -l component=taskmanager --tail 20
```
Expected: `Processing: dev-XXXXXX` messages

#### Check ClickHouse has data:
```bash
kubectl exec -n clickhouse chi-iot-cluster-repl-iot-cluster-1-0-0 -- \
  clickhouse-client --query "SELECT COUNT(*) FROM benchmark.sensors_distributed"
```
Expected: Growing number

#### Access Grafana:
```bash
kubectl port-forward -n pulsar svc/pulsar-grafana 3000:80
```
Open: http://localhost:3000 (admin/admin123)

**Dashboards:**
- **Flink Metrics**: Shows throughput, latency, records in/out
- **ClickHouse Data**: Shows device counts, latest data, temperature ranges

---

## 🆘 Troubleshooting

### Problem: ClickHouse tables missing on some replicas

**Solution:**
```bash
cd clickhouse-load
./00-create-schema-all-replicas.sh
```

The script will show exactly which replicas are missing tables.

---

### Problem: Flink not sending data to ClickHouse

**Check 1:** Tables exist on all replicas (run schema script)
**Check 2:** Delete TaskManager pods to force new JDBC connections
```bash
kubectl delete pod -n flink-benchmark -l component=taskmanager
```

New TaskManager pods will automatically start and get fresh connections to ClickHouse.

---

### Problem: Grafana dashboards not showing data

**Check 1:** Verify data is in ClickHouse
```bash
kubectl exec -n clickhouse chi-iot-cluster-repl-iot-cluster-1-0-0 -- \
  clickhouse-client --query "SELECT COUNT(*) FROM benchmark.sensors_distributed WHERE time >= now() - INTERVAL 1 MINUTE"
```

**Check 2:** Re-run dashboard import
```bash
cd grafana-dashboards
./import-dashboards.sh
```

---

## 📊 What Runs Where

| Component | Namespace | Purpose |
|-----------|-----------|---------|
| ClickHouse | `clickhouse` | Data storage |
| Pulsar | `pulsar` | Message broker + monitoring |
| Grafana | `pulsar` | Metrics visualization |
| Victoria Metrics | `pulsar` | Metrics storage |
| Flink Operator | `flink-operator` | Manages Flink deployments |
| Flink Job | `flink-benchmark` | Consumes from Pulsar → writes to ClickHouse |

---

## ⚡ Quick Commands

### Port Forwards (run these in separate terminals)
```bash
# Grafana dashboards
kubectl port-forward -n pulsar svc/pulsar-grafana 3000:80

# Flink dashboard
kubectl port-forward -n flink-benchmark svc/iot-flink-job-rest 8081:8081

# Flink metrics (direct)
kubectl port-forward -n flink-benchmark $(kubectl get pod -n flink-benchmark -l app=iot-flink-job -o name | head -1) 9249:9249
```

### Check Status
```bash
# All namespaces
kubectl get pods -A | grep -E "clickhouse|flink|pulsar|grafana"

# Check data flow
kubectl exec -n clickhouse chi-iot-cluster-repl-iot-cluster-1-0-0 -- \
  clickhouse-client --query "SELECT COUNT(*) as total, max(time) as latest FROM benchmark.sensors_distributed"
```

---

## 🔄 Complete Cleanup (Start Fresh)

```bash
# Delete everything
kubectl delete namespace flink-benchmark clickhouse pulsar

# Wait for cleanup
kubectl get namespaces -w

# Redeploy from Step 1
```

---

**Last Updated:** October 9, 2025  
**Total Deployment Time:** ~10 minutes

