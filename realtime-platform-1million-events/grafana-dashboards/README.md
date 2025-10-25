# Grafana Dashboards for Kubernetes/AWS Deployment

This directory contains pre-configured Grafana dashboards for monitoring your Flink IoT pipeline in Kubernetes.

## 📊 Available Dashboards

1. **flink-dashboard.json** - Flink Processing Metrics
   - Records In/Out Per Second
   - CPU & Memory Usage
   - Operator Latency
   - JVM Heap Memory
   - Cluster Statistics

2. **clickhouse-dashboard.json** - ClickHouse Data Metrics
   - Total Records & Ingestion Rate
   - Unique Devices
   - Temperature Statistics
   - Humidity & Battery Levels
   - Device Type Distribution
   - Top Devices Table

## 🚀 How to Use in Kubernetes

### Option 1: Import via Grafana UI (Recommended)

1. **Access Grafana:**
   ```bash
   kubectl port-forward -n pulsar svc/pulsar-grafana 3000:80
   ```
   Open: http://localhost:3000 (admin/admin)

2. **Configure Datasources:**
   - Go to **Configuration** → **Data Sources**
   - Add **Prometheus** datasource:
     - Name: `Prometheus`
     - UID: `prometheus` (important!)
     - URL: `http://pulsar-grafana-prometheus-server.pulsar.svc.cluster.local:80`
   
   - Add **ClickHouse** datasource:
     - Install plugin first: `grafana-clickhouse-datasource`
     - Name: `ClickHouse`
     - UID: `clickhouse` (important!)
     - URL: `http://clickhouse-iot-cluster-repl.clickhouse.svc.cluster.local:8123`
     - Default Database: `benchmark`

3. **Import Dashboards:**
   - Go to **Dashboards** → **Import**
   - Upload `flink-dashboard.json`
   - Select **Prometheus** datasource
   - Click **Import**
   
   - Repeat for `clickhouse-dashboard.json`
   - Select **ClickHouse** datasource

### Option 2: ConfigMap Provisioning

1. **Create ConfigMap for datasources:**
   ```bash
   kubectl create configmap grafana-datasources \
     --from-file=grafana-datasource-k8s.yaml \
     -n pulsar
   ```

2. **Create ConfigMaps for dashboards:**
   ```bash
   kubectl create configmap grafana-dashboard-flink \
     --from-file=flink-dashboard.json \
     -n pulsar
   
   kubectl create configmap grafana-dashboard-clickhouse \
     --from-file=clickhouse-dashboard.json \
     -n pulsar
   ```

3. **Mount ConfigMaps to Grafana Pod:**
   Update your Grafana deployment to mount these ConfigMaps at:
   - Datasources: `/etc/grafana/provisioning/datasources/`
   - Dashboards: `/etc/grafana/provisioning/dashboards/`

### Option 3: Helm Values (If using Pulsar Helm Chart)

Add to your `values.yaml`:

```yaml
grafana:
  enabled: true
  adminPassword: admin
  
  # Datasources
  datasources:
    datasources.yaml:
      apiVersion: 1
      datasources:
        - name: Prometheus
          type: prometheus
          uid: prometheus
          url: http://pulsar-grafana-prometheus-server:80
          isDefault: true
        
        - name: ClickHouse
          type: grafana-clickhouse-datasource
          uid: clickhouse
          url: http://clickhouse-iot-cluster-repl.clickhouse.svc.cluster.local:8123
          jsonData:
            defaultDatabase: benchmark
  
  # Dashboards
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
        - name: 'default'
          orgId: 1
          folder: 'IoT Pipeline'
          type: file
          disableDeletion: false
          editable: true
          options:
            path: /var/lib/grafana/dashboards/default
  
  dashboardsConfigMaps:
    default: "grafana-dashboards"
```

## 🔧 Adjusting Datasource URLs

If your service names are different, update these in `grafana-datasource-k8s.yaml`:

**Prometheus URL:**
- Default: `http://pulsar-grafana-prometheus-server.pulsar.svc.cluster.local:80`
- Check your service: `kubectl get svc -n pulsar | grep prometheus`

**ClickHouse URL:**
- Default: `http://clickhouse-iot-cluster-repl.clickhouse.svc.cluster.local:8123`
- Check your service: `kubectl get svc -n clickhouse | grep clickhouse`

**Format:** `http://<service-name>.<namespace>.svc.cluster.local:<port>`

## 📈 Dashboard Access URLs

Once imported, access dashboards at:
- **Flink Metrics**: http://localhost:3000/d/flink-iot-pipeline
- **ClickHouse Data**: http://localhost:3000/d/clickhouse-iot-metrics

## ✅ Prerequisites

1. **Flink must be configured with Prometheus metrics reporter**
   - Use the `flink-conf.yaml` from `../flink-load/`
   - Ensure Flink pods expose port 9249 for metrics

2. **Prometheus must be scraping Flink metrics**
   - Add Flink service monitors or pod annotations
   - Verify: Check Prometheus targets at `/targets`

3. **ClickHouse must be accessible**
   - Verify connection: `kubectl exec -it <grafana-pod> -- curl http://clickhouse-iot-cluster-repl.clickhouse.svc.cluster.local:8123`

4. **Grafana plugins installed**
   - ClickHouse datasource plugin: `grafana-clickhouse-datasource`
   - Install via: `grafana-cli plugins install grafana-clickhouse-datasource`

## 🔍 Troubleshooting

### Dashboard shows "No Data"

1. **Check datasource UIDs match:**
   ```bash
   # In Grafana UI, check datasource UID
   # Must be: "prometheus" and "clickhouse"
   ```

2. **Verify datasource connectivity:**
   - Test in Grafana UI: Data Sources → Test
   - Check service endpoints are correct

3. **Check Prometheus is scraping Flink:**
   ```bash
   # Port forward to Prometheus
   kubectl port-forward -n pulsar svc/pulsar-grafana-prometheus-server 9090:80
   
   # Open http://localhost:9090/targets
   # Look for Flink targets
   ```

4. **Verify Flink metrics are exposed:**
   ```bash
   kubectl port-forward -n <namespace> <flink-jobmanager-pod> 9249:9249
   curl http://localhost:9249/metrics | grep flink_
   ```

### ClickHouse dashboard not loading

1. **Install ClickHouse plugin:**
   ```bash
   kubectl exec -it <grafana-pod> -n pulsar -- grafana-cli plugins install grafana-clickhouse-datasource
   kubectl rollout restart deployment/pulsar-grafana -n pulsar
   ```

2. **Verify ClickHouse service:**
   ```bash
   kubectl get svc -n clickhouse
   kubectl exec -it <grafana-pod> -n pulsar -- curl http://clickhouse-iot-cluster-repl.clickhouse.svc.cluster.local:8123
   ```

## 📝 Notes

- Dashboard auto-refresh is set to **5 seconds**
- Default time range is **Last 15 minutes**
- Both dashboards use the same datasource UIDs as local Docker setup for consistency
- The dashboards are pre-configured and ready to use - no modifications needed if datasource UIDs match

## 🔗 Related Files

- `../flink-load/flink-conf.yaml` - Flink configuration with Prometheus metrics
- `../flink-load/flink-consumer/` - Updated Flink consumer with batch inserts
- `grafana-datasource-k8s.yaml` - Kubernetes datasource configuration

