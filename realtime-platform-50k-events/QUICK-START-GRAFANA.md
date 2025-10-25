# Quick Start - Grafana Dashboards for Flink Metrics

## 🚀 Complete Setup (One Command)

```bash
# Step 1: Setup Flink metrics and Prometheus scraping
cd /Users/vijayabhaskarv/IOT/datapipeline-0/Flink-Benchmark/low_infra_flink/flink-load
./setup-flink-metrics.sh

# Step 2: Import Grafana dashboards
cd ../grafana-dashboards
./import-dashboards.sh
```

## 📊 Access Dashboards

Once setup is complete, open your browser:

**Flink Metrics:**
http://localhost:3000/d/flink-iot-pipeline/flink-iot-pipeline-metrics

**ClickHouse Data:**
http://localhost:3000/d/clickhouse-iot-metrics/clickhouse-iot-data-metrics

**Login:** admin / admin123

## ✅ What Was Configured

### For Local Docker (aws-deploy):
- ✓ Flink with Prometheus metrics reporter
- ✓ Prometheus scraping Flink
- ✓ Grafana with both dashboards auto-loaded
- ✓ Performance producer (100 msg/sec)
- ✓ Batch inserts to ClickHouse (100 records/batch)

### For Kubernetes/AWS (Flink-Benchmark/low_infra_flink):
- ✓ FlinkDeployment patched with Prometheus metrics
- ✓ Victoria Metrics VMPodScrape configured
- ✓ Grafana dashboards with distributed table queries
- ✓ ClickHouse plugin installed

## 📈 Current Metrics

**Flink Processing:**
- Throughput: ~16,000 records/second
- Job Status: RUNNING
- TaskManagers: Active

**ClickHouse Storage:**
- Total Records: 3,192,900+ (and growing)
- Unique Devices: 100,187
- Data distributed across shards

## 🔍 Troubleshooting

### ClickHouse Dashboard Shows No Data

**If you see "No Data" in ClickHouse panels:**

1. **Check ClickHouse plugin is installed:**
   ```bash
   kubectl exec -n pulsar deployment/pulsar-grafana -- grafana-cli plugins ls | grep clickhouse
   ```

2. **Install if missing:**
   ```bash
   kubectl exec -n pulsar deployment/pulsar-grafana -- grafana-cli plugins install grafana-clickhouse-datasource
   kubectl rollout restart deployment/pulsar-grafana -n pulsar
   ```

3. **Wait for Grafana to restart (2-3 minutes)**

4. **Recreate datasource and reimport dashboard:**
   ```bash
   cd Flink-Benchmark/low_infra_flink/grafana-dashboards
   ./import-dashboards.sh
   ```

5. **Verify data exists:**
   ```bash
   kubectl exec -n clickhouse chi-iot-cluster-repl-iot-cluster-1-0-0 -- \
     clickhouse-client --query "SELECT COUNT(*) FROM benchmark.sensors_distributed"
   ```

### Flink Dashboard Shows No Data

1. **Check Victoria Metrics is scraping:**
   ```bash
   kubectl port-forward -n pulsar svc/vmsingle-pulsar-victoria-metrics-k8s-stack 8429:8429
   # Open: http://localhost:8429/api/v1/query?query=flink_jobmanager_numRunningJobs
   ```

2. **Check VMPodScrape exists:**
   ```bash
   kubectl get vmpodscrape flink-metrics -n pulsar
   ```

3. **Verify Flink metrics endpoint:**
   ```bash
   kubectl port-forward -n flink-benchmark pod/<flink-pod> 9249:9249
   curl http://localhost:9249/metrics | grep flink_
   ```

## 📂 File Locations

**Kubernetes/AWS Setup:**
- Setup script: `Flink-Benchmark/low_infra_flink/flink-load/setup-flink-metrics.sh`
- Import script: `Flink-Benchmark/low_infra_flink/grafana-dashboards/import-dashboards.sh`
- Dashboards: `Flink-Benchmark/low_infra_flink/grafana-dashboards/*.json`
- Config files: `Flink-Benchmark/low_infra_flink/flink-load/*.yaml`

**Local Docker Setup:**
- Start script: `aws-deploy/scripts/start-pipeline.sh`
- Stop script: `aws-deploy/scripts/stop-pipeline.sh`
- Config: `aws-deploy/config/`
- Dashboards: Auto-loaded on startup

## 🎯 Key Points

1. **Use distributed tables** in ClickHouse dashboards (sensors_distributed, not sensors_local)
2. **Victoria Metrics** is used instead of Prometheus in Kubernetes
3. **VMPodScrape** tells Victoria Metrics to scrape Flink pods
4. **Plugin must be installed** for ClickHouse datasource to work
5. **Port-forward required** for local access to Kubernetes services

## ✅ Verification Commands

```bash
# Check Flink is running
kubectl get pods -n flink-benchmark | grep flink

# Check data in ClickHouse
kubectl exec -n clickhouse chi-iot-cluster-repl-iot-cluster-1-0-0 -- \
  clickhouse-client --query "SELECT COUNT(*) FROM benchmark.sensors_distributed"

# Check Flink metrics
kubectl port-forward -n flink-benchmark pod/<flink-jobmanager-pod> 9249:9249 &
curl http://localhost:9249/metrics | grep flink_jobmanager_numRunningJobs

# Access Grafana
kubectl port-forward -n pulsar svc/pulsar-grafana 3000:80 &
# Open: http://localhost:3000
```

