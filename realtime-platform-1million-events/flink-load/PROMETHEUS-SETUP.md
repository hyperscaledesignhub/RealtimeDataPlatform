# Flink Prometheus Metrics Setup for AWS/Kubernetes

This guide explains how to configure Flink to expose metrics that can be scraped by Prometheus (from Pulsar deployment).

## 📋 Prerequisites

1. Flink deployed in Kubernetes
2. Pulsar with Prometheus deployed (has Prometheus Operator)
3. Kubectl access to your cluster

## 🚀 Setup Methods

### Method 1: Using ServiceMonitor (Recommended for Prometheus Operator)

If your Pulsar deployment uses Prometheus Operator, use ServiceMonitor:

1. **Create ConfigMap with Flink configuration:**
   ```bash
   kubectl apply -f flink-config-configmap.yaml
   ```

2. **Apply ServiceMonitor and Services:**
   ```bash
   kubectl apply -f flink-servicemonitor.yaml
   ```

3. **Update your Flink deployments** to:
   - Mount the ConfigMap
   - Download Prometheus JAR (via initContainer)
   - Expose port 9249

   See `flink-prometheus-annotations.yaml` for complete examples.

### Method 2: Using Pod Annotations (Simpler)

If Prometheus is configured to discover pods via annotations:

1. **Create ConfigMap:**
   ```bash
   kubectl apply -f flink-config-configmap.yaml
   ```

2. **Add these annotations to your Flink pods:**
   ```yaml
   annotations:
     prometheus.io/scrape: "true"
     prometheus.io/port: "9249"
     prometheus.io/path: "/metrics"
   ```

3. **Update pod spec** to mount config and download Prometheus JAR.

   See `flink-prometheus-annotations.yaml` for complete examples.

## 🔧 Step-by-Step Setup

### Step 1: Create Flink Config ConfigMap

```bash
cd /path/to/Flink-Benchmark/low_infra_flink/flink-load/

# Edit the namespace in the file first
kubectl apply -f flink-config-configmap.yaml
```

### Step 2: Update Flink Deployments

**Option A: Using Helm (if you deployed Flink via Helm)**

Add to your `values.yaml`:

```yaml
jobmanager:
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "9249"
    prometheus.io/path: "/metrics"
  
  extraPorts:
    - name: metrics
      containerPort: 9249
  
  extraVolumes:
    - name: flink-config
      configMap:
        name: flink-config
    - name: flink-prometheus-jar
      emptyDir: {}
  
  extraVolumeMounts:
    - name: flink-config
      mountPath: /opt/flink/conf/flink-conf.yaml
      subPath: flink-conf.yaml
    - name: flink-prometheus-jar
      mountPath: /opt/flink/lib/flink-metrics-prometheus-1.18.0.jar
      subPath: flink-metrics-prometheus-1.18.0.jar
  
  initContainers:
    - name: download-prometheus-jar
      image: curlimages/curl:latest
      command:
        - sh
        - -c
        - |
          curl -L https://repo1.maven.org/maven2/org/apache/flink/flink-metrics-prometheus/1.18.0/flink-metrics-prometheus-1.18.0.jar \
            -o /opt/flink/lib/flink-metrics-prometheus-1.18.0.jar
      volumeMounts:
        - name: flink-prometheus-jar
          mountPath: /opt/flink/lib

taskmanager:
  # Same configuration as jobmanager
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "9249"
    prometheus.io/path: "/metrics"
  # ... (repeat extraPorts, extraVolumes, etc.)
```

**Option B: Patch Existing Deployments**

```bash
# Get your current Flink deployment
kubectl get deployment -n <namespace> | grep flink

# Edit the deployment
kubectl edit deployment flink-jobmanager -n <namespace>

# Add the annotations, ports, volumes, and initContainers from flink-prometheus-annotations.yaml
```

### Step 3: Create ServiceMonitor (if using Prometheus Operator)

```bash
# Edit namespace in the file first
kubectl apply -f flink-servicemonitor.yaml
```

### Step 4: Verify Setup

```bash
# Check if Flink pods are running with new config
kubectl get pods -n <namespace> | grep flink

# Check if metrics port is exposed
kubectl port-forward -n <namespace> pod/<flink-jobmanager-pod> 9249:9249

# In another terminal, test metrics endpoint
curl http://localhost:9249/metrics | grep flink_

# Check if Prometheus is scraping (port-forward to Prometheus)
kubectl port-forward -n pulsar svc/pulsar-grafana-prometheus-server 9090:80

# Open http://localhost:9090/targets
# Look for flink-metrics targets
```

## 🔍 Troubleshooting

### Metrics endpoint not accessible

1. **Check if pod has metrics port:**
   ```bash
   kubectl describe pod <flink-jobmanager-pod> -n <namespace> | grep 9249
   ```

2. **Check if Prometheus JAR is loaded:**
   ```bash
   kubectl exec -it <flink-jobmanager-pod> -n <namespace> -- ls -la /opt/flink/lib/ | grep prometheus
   ```

3. **Check Flink logs:**
   ```bash
   kubectl logs <flink-jobmanager-pod> -n <namespace> | grep -i "prometheus\|metric"
   ```

### Prometheus not scraping Flink

1. **Check ServiceMonitor is created:**
   ```bash
   kubectl get servicemonitor -n <namespace>
   ```

2. **Verify ServiceMonitor labels match Prometheus selector:**
   ```bash
   # Check what labels Prometheus expects
   kubectl get prometheus -n pulsar -o yaml | grep serviceMonitorSelector
   ```

3. **Check Prometheus configuration:**
   ```bash
   kubectl port-forward -n pulsar svc/pulsar-grafana-prometheus-server 9090:80
   # Open http://localhost:9090/config
   # Look for flink scrape configs
   ```

4. **Check if Services exist:**
   ```bash
   kubectl get svc -n <namespace> | grep flink-.*-metrics
   ```

### Flink pods not starting

1. **Check init container logs:**
   ```bash
   kubectl logs <flink-pod> -n <namespace> -c download-prometheus-jar
   ```

2. **Check if ConfigMap exists:**
   ```bash
   kubectl get configmap flink-config -n <namespace>
   ```

## 📊 Verify in Grafana

Once Prometheus is scraping Flink:

1. **Port-forward to Grafana:**
   ```bash
   kubectl port-forward -n pulsar svc/pulsar-grafana 3000:80
   ```

2. **Open Grafana:** http://localhost:3000

3. **Check Prometheus datasource:**
   - Go to Configuration → Data Sources
   - Test Prometheus connection

4. **Query Flink metrics:**
   - Go to Explore
   - Query: `flink_jobmanager_numRunningJobs`
   - Should return data

5. **Import dashboards:**
   - Import `flink-dashboard.json` from `../grafana-dashboards/`

## 🔗 Important Service Names

Update these in your configuration if different:

- **Prometheus Service**: `pulsar-grafana-prometheus-server.pulsar.svc.cluster.local:80`
- **Flink JobManager**: `flink-jobmanager.<namespace>.svc.cluster.local:9249`
- **Flink TaskManager**: Pod-based scraping via ServiceMonitor

## 📝 Quick Reference

**Key files:**
- `flink-config-configmap.yaml` - Flink configuration with Prometheus reporter
- `flink-servicemonitor.yaml` - ServiceMonitor for Prometheus Operator
- `flink-prometheus-annotations.yaml` - Complete pod spec examples

**Key metrics to verify:**
- `flink_jobmanager_numRunningJobs`
- `flink_taskmanager_job_task_operator_numRecordsInPerSecond`
- `flink_taskmanager_Status_JVM_CPU_Load`

**Ports:**
- 9249: Flink metrics (Prometheus format)
- 8081: Flink Web UI
- 6123: Flink RPC

## ✅ Success Checklist

- [ ] ConfigMap created with flink-conf.yaml
- [ ] Flink pods restarted with new config
- [ ] Port 9249 exposed on Flink pods
- [ ] Prometheus JAR downloaded in initContainer
- [ ] Metrics endpoint accessible (curl test)
- [ ] ServiceMonitor/annotations configured
- [ ] Prometheus scraping Flink (check /targets)
- [ ] Metrics visible in Grafana
- [ ] Dashboards imported and working

