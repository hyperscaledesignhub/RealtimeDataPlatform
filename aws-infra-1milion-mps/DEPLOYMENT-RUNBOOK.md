# Platform Deployment Runbook

This runbook provides the **exact step-by-step sequence** to deploy and run the complete event streaming platform from scratch.

## Platform Overview

This platform is designed for **high-throughput event processing** across multiple domains:
- **E-Commerce:** Order processing, inventory tracking, customer events
- **Finance:** Transaction processing, market data, payment events
- **IoT:** Sensor telemetry, device monitoring, alert processing
- **Gaming:** Player events, leaderboards, in-game transactions
- **Logistics:** Package tracking, fleet management, route optimization
- **Social Media:** User interactions, content streams, engagement metrics

The same infrastructure handles **30K-250K messages/second** regardless of domain.

## Prerequisites

✅ AWS CLI configured with credentials  
✅ Terraform installed (v1.0+)  
✅ kubectl installed (v1.28+)  
✅ Docker installed  
✅ Helm installed (v3.x)

---

## Deployment Sequence

### Step 1: Deploy Infrastructure with Terraform

Create the AWS infrastructure (VPC, EKS cluster, node groups).

```bash
# Navigate to infrastructure directory
cd /Users/vijayabhaskarv/IOT/github/RealtimeDataPlatform/aws-infra-1milion-mps

# Initialize Terraform (downloads providers and modules)
terraform init

# Review what will be created
terraform plan

# Deploy infrastructure (creates VPC, EKS, all node groups)
terraform apply
# Type 'yes' when prompted

# Wait for completion (~15-20 minutes)
```

**What this creates:**
- VPC with public and private subnets
- EKS cluster (bench-low-infra)
- 9 node groups (Producer, Pulsar ZK/Broker/Proxy, Flink JM/TM, ClickHouse, General)
- S3 bucket for Flink state
- IAM roles and policies
- ECR repositories

**Verify:**
```bash
# Configure kubectl
aws eks update-kubeconfig --region us-west-2 --name bench-low-infra

# Check cluster is accessible
kubectl get nodes

# You should see nodes in Ready state
```

---

### Step 2: Deploy Pulsar

Deploy Apache Pulsar message broker (ZooKeeper, Broker, BookKeeper, Proxy).

```bash
# Navigate to Pulsar directory
cd pulsar-load

# Run deployment script
./deploy.sh

# Wait for all pods to be ready (~5-10 minutes)
kubectl get pods -n pulsar -w
# Press Ctrl+C when all pods are Running
```

**What this deploys:**
- cert-manager (for TLS certificates)
- Pulsar cluster using Helm chart
  - ZooKeeper: 3 nodes
  - Broker: 3 nodes
  - BookKeeper: 3 nodes with NVMe storage
  - Proxy: 2 nodes
  - Toolset: 1 pod (admin utilities)

**Verify:**
```bash
# Check all Pulsar pods are running
kubectl get pods -n pulsar

# Verify Pulsar cluster is healthy
kubectl exec -n pulsar pulsar-toolset-0 -- \
  bin/pulsar-admin brokers healthcheck

# List brokers
kubectl exec -n pulsar pulsar-toolset-0 -- \
  bin/pulsar-admin brokers list pulsar-cluster
```

---

### Step 3: Install ClickHouse

Deploy ClickHouse database cluster.

```bash
# Navigate to ClickHouse directory
cd ../clickhouse-load

# Install ClickHouse Operator and Cluster
./00-install-clickhouse.sh

# Wait for ClickHouse pods to be ready (~3-5 minutes)
kubectl get pods -n clickhouse -w
# Press Ctrl+C when all pods are Running
```

**What this deploys:**
- ClickHouse Operator
- ClickHouse cluster with 3-6 replicas
- Persistent volumes for data storage

**Verify:**
```bash
# Check ClickHouse pods
kubectl get pods -n clickhouse

# Test ClickHouse connectivity
kubectl exec -n clickhouse chi-iot-cluster-repl-iot-cluster-0-0-0 -- \
  clickhouse-client --query "SELECT 1"
```

---

### Step 4: Create ClickHouse Schema

Create database tables on all ClickHouse replicas.

```bash
# Still in clickhouse-load directory

# Create schema on all replicas
./00-create-schema-all-replicas.sh
```

**What this creates:**
- Database: `benchmark`
- Table: `benchmark.sensors_local` (25 fields for IoT sensor data)
- Table: `benchmark.cpu_local` (30+ fields for CPU metrics)
- Materialized columns (has_alert, total_usage)
- Replication configuration

**Verify:**
```bash
# Check databases
kubectl exec -n clickhouse chi-iot-cluster-repl-iot-cluster-0-0-0 -- \
  clickhouse-client --query "SHOW DATABASES"

# Check tables
kubectl exec -n clickhouse chi-iot-cluster-repl-iot-cluster-0-0-0 -- \
  clickhouse-client --query "SHOW TABLES FROM benchmark"

# Verify schema
kubectl exec -n clickhouse chi-iot-cluster-repl-iot-cluster-0-0-0 -- \
  clickhouse-client --query "DESCRIBE benchmark.sensors_local"
```

---

### Step 5: Deploy Flink Operator

Install Flink Kubernetes Operator.

```bash
# Navigate to Flink directory
cd ../flink-load

# Deploy Flink Operator (installs cert-manager and operator)
./deploy.sh

# Wait for operator to be ready (~2-3 minutes)
kubectl get pods -n flink-operator -w
# Press Ctrl+C when operator pod is Running
```

**What this deploys:**
- cert-manager (if not already installed)
- Flink Kubernetes Operator v1.7.0
- Custom Resource Definitions (CRDs) for FlinkDeployment

**Verify:**
```bash
# Check Flink Operator is running
kubectl get pods -n flink-operator

# Check CRDs are installed
kubectl get crd | grep flink
```

---

### Step 6: Setup S3 for Flink Checkpoints

Configure S3 as the checkpoint storage backend.

```bash
# Still in flink-load directory

# Setup S3 checkpoint configuration
./setup-s3-checkpoints.sh
```

**What this does:**
- Configures S3 bucket for checkpoints and savepoints
- Sets up IAM permissions
- Creates Kubernetes secrets for S3 access

**Verify:**
```bash
# Check S3 bucket exists
aws s3 ls | grep flink-state

# Check secrets are created (if any)
kubectl get secrets -n flink-benchmark
```

---

### Step 7: Apply Flink ConfigMap

Create ConfigMap with Flink configuration (non-partitioned setup).

```bash
# Still in flink-load directory

# Apply Flink configuration ConfigMap
kubectl apply -f flink-config-configmap.yaml -n flink-benchmark

# Verify ConfigMap
kubectl get configmap -n flink-benchmark
kubectl describe configmap flink-config -n flink-benchmark
```

**Note:** We're **not** using partition commands - this is a single topic consumption setup.

---

### Step 8: Deploy Flink Job

Deploy the Flink streaming job that processes IoT data.

```bash
# Still in flink-load directory

# Build and push Flink job image to ECR (if not already done)
./build-and-push.sh

# Deploy Flink job using FlinkDeployment CRD
kubectl apply -f flink-job-deployment.yaml

# Wait for Flink pods to start (~2-3 minutes)
kubectl get pods -n flink-benchmark -w
# Press Ctrl+C when JobManager and TaskManagers are Running
```

**What this deploys:**
- JobManager: 1 pod (job coordination)
- TaskManager: 2+ pods (parallel processing)
- Flink job: JDBCFlinkConsumer (consumes from Pulsar, aggregates, writes to ClickHouse)

**Verify:**
```bash
# Check Flink deployment status
kubectl get flinkdeployment -n flink-benchmark

# Check Flink pods
kubectl get pods -n flink-benchmark

# Check JobManager logs
kubectl logs -n flink-benchmark -l app=iot-flink-job,component=jobmanager

# Check TaskManager logs
kubectl logs -n flink-benchmark -l app=iot-flink-job,component=taskmanager
```

---

### Step 9: Setup Flink Monitoring

Enable Prometheus metrics collection for Flink.

```bash
# Still in flink-load directory

# Setup Flink metrics monitoring
./setup-flink-metrics.sh

# Start monitoring Flink metrics
./monitor-flink.sh
```

**What this does:**
- Configures Prometheus ServiceMonitor for Flink
- Exposes Flink metrics endpoint
- Sets up metric collection

**Verify:**
```bash
# Check ServiceMonitor
kubectl get servicemonitor -n flink-benchmark

# Check Flink metrics endpoint
kubectl port-forward -n flink-benchmark <jobmanager-pod> 9249:9249 &
curl http://localhost:9249/metrics
```

---

### Step 10: Import Grafana Dashboards

Import pre-configured dashboards for Pulsar, Flink, and ClickHouse.

```bash
# Navigate to Grafana dashboards directory
cd ../grafana-dashboards

# Import all dashboards
./import-dashboards.sh
```

**What this imports:**
- Pulsar dashboard (broker metrics, topic stats, throughput)
- Flink dashboard (job metrics, checkpoints, backpressure)
- ClickHouse dashboard (query performance, table sizes, ingestion rate)

**Verify:**
```bash
# Check Grafana pod is running
kubectl get pods -n pulsar | grep grafana

# The dashboards will be visible after port-forwarding (Step 12)
```

---

### Step 11: Deploy Event Producer

Deploy the event producer with partitioned topic support for high throughput (250K msg/sec per pod).

```bash
# Navigate to Producer directory
cd ../producer-load

# Build and push producer image to ECR (if not already done)
./build-and-push.sh

# Deploy producer with partition support (250K msg/sec per pod)
./deploy-with-partitions.sh
```

**What this deploys:**
- Producer pods: 3+ instances
- Each pod: 250K messages/second
- Total throughput: 750K+ messages/second
- AVRO-encoded event messages to Pulsar
- Adaptable for any domain (e-commerce, finance, IoT, gaming, etc.)

**Verify:**
```bash
# Check producer pods are running
kubectl get pods -n iot-pipeline

# Check producer logs
kubectl logs -f -n iot-pipeline -l app=iot-producer

# You should see messages like:
# "Sent 250000 messages in last second"
```

---

### Step 12: Access Grafana Dashboard

Port-forward the Grafana service and access the web UI.

```bash
# Port-forward Grafana service in pulsar namespace to local port 3000
kubectl port-forward -n pulsar svc/grafana 3000:3000
```

**Access Grafana:**

1. Open browser: **http://localhost:3000**

2. **Login credentials:**
   - Username: `admin`
   - Password: `admin123`

3. **First login:**
   - You may be prompted to change password (optional)
   - Click "Skip" if you don't want to change

---

### Step 13: View Metrics and Dashboards

Navigate through Grafana to view real-time metrics.

#### View Pulsar Metrics

1. On the left menu, click **"Dashboards"** (four squares icon)
2. In the search box, type **"Pulsar"**
3. Click on **"Apache Pulsar Dashboard"**

**Metrics visible:**
- Broker throughput (messages in/out per second)
- Topic statistics
- Storage size
- Producer/consumer connections
- Backlog size
- Message rate per topic

#### View ClickHouse Metrics

1. On the left menu, click **"Dashboards"**
2. In the search box, type **"ClickHouse"**
3. Click on **"ClickHouse Dashboard"**

**Metrics visible:**
- Query execution time
- Rows read/written per second
- Table sizes and compression ratio
- Memory usage
- CPU utilization
- INSERT/SELECT queries per second
- Active connections

#### View Flink Metrics

1. On the left menu, click **"Dashboards"**
2. In the search box, type **"Flink"**
3. Click on **"Apache Flink Dashboard"**

**Metrics visible:**
- Records processed per second
- Checkpoint duration and success rate
- Task backpressure
- Memory usage (heap/non-heap)
- CPU utilization
- Watermark lag
- Kafka/Pulsar consumer lag
- Task failures and restarts

---

## Complete Command Reference

Here's the complete sequence in one place for easy copy-paste:

```bash
# ============================================================================
# COMPLETE DEPLOYMENT SEQUENCE
# ============================================================================

# Step 1: Deploy Infrastructure
cd /Users/vijayabhaskarv/IOT/github/RealtimeDataPlatform/aws-infra-1milion-mps
terraform init
terraform plan
terraform apply  # Type 'yes'
aws eks update-kubeconfig --region us-west-2 --name bench-low-infra
kubectl get nodes

# Step 2: Deploy Pulsar
cd pulsar-load
./deploy.sh
kubectl get pods -n pulsar -w  # Wait until all Running

# Step 3: Install ClickHouse
cd ../clickhouse-load
./00-install-clickhouse.sh
kubectl get pods -n clickhouse -w  # Wait until all Running

# Step 4: Create Schema
./00-create-schema-all-replicas.sh

# Step 5: Deploy Flink Operator
cd ../flink-load
./deploy.sh
kubectl get pods -n flink-operator -w  # Wait until Running

# Step 6: Setup S3 Checkpoints
./setup-s3-checkpoints.sh

# Step 7: Apply ConfigMap
kubectl apply -f flink-config-configmap.yaml -n flink-benchmark

# Step 8: Deploy Flink Job
./build-and-push.sh
kubectl apply -f flink-job-deployment.yaml
kubectl get pods -n flink-benchmark -w  # Wait until all Running

# Step 9: Setup Monitoring
./setup-flink-metrics.sh
./monitor-flink.sh

# Step 10: Import Dashboards
cd ../grafana-dashboards
./import-dashboards.sh

# Step 11: Deploy Producer
cd ../producer-load
./build-and-push.sh
./deploy-with-partitions.sh
kubectl get pods -n iot-pipeline -w  # Wait until all Running

# Step 12: Port-forward Grafana
kubectl port-forward -n pulsar svc/grafana 3000:3000

# Step 13: Access Grafana
# Open browser: http://localhost:3000
# Login: admin / admin123
# View dashboards: Pulsar, ClickHouse, Flink
```

---

## Verification Commands

After deployment, use these commands to verify the system is working:

```bash
# 1. Check producer is sending messages
kubectl logs -n iot-pipeline -l app=iot-producer | grep "Sent"

# 2. Check Pulsar topic has messages
kubectl exec -n pulsar pulsar-toolset-0 -- \
  bin/pulsar-admin topics stats persistent://public/default/iot-sensor-data

# 3. Check Flink is consuming and processing
kubectl logs -n flink-benchmark -l component=taskmanager | grep "Aggregated"

# 4. Check data is arriving in ClickHouse
kubectl exec -n clickhouse chi-iot-cluster-repl-iot-cluster-0-0-0 -- \
  clickhouse-client --query "SELECT count() FROM benchmark.sensors_local"

# 5. Query recent data
kubectl exec -n clickhouse chi-iot-cluster-repl-iot-cluster-0-0-0 -- \
  clickhouse-client --query "
    SELECT 
      device_id, 
      device_type, 
      temperature, 
      humidity, 
      time 
    FROM benchmark.sensors_local 
    ORDER BY time DESC 
    LIMIT 10"

# 6. Check end-to-end throughput
# Producer: Check logs for msg/sec
kubectl logs -n iot-pipeline -l app=iot-producer --tail=10

# Pulsar: Check topic throughput
kubectl exec -n pulsar pulsar-toolset-0 -- \
  bin/pulsar-admin topics stats persistent://public/default/iot-sensor-data | grep msgRateIn

# Flink: Check via UI at http://localhost:8081 (after port-forward)
kubectl port-forward -n flink-benchmark svc/iot-flink-job-rest 8081:8081

# ClickHouse: Check insert rate
kubectl exec -n clickhouse chi-iot-cluster-repl-iot-cluster-0-0-0 -- \
  clickhouse-client --query "
    SELECT 
      toStartOfMinute(time) as minute,
      count() as records_per_minute
    FROM benchmark.sensors_local
    WHERE time >= now() - INTERVAL 10 MINUTE
    GROUP BY minute
    ORDER BY minute DESC"
```

---

## Expected Timeline

| Step | Time Required | Total Elapsed |
|------|---------------|---------------|
| 1. Terraform Infrastructure | 15-20 min | 20 min |
| 2. Deploy Pulsar | 5-10 min | 30 min |
| 3. Install ClickHouse | 3-5 min | 35 min |
| 4. Create Schema | 1 min | 36 min |
| 5. Deploy Flink Operator | 2-3 min | 39 min |
| 6. Setup S3 Checkpoints | 1 min | 40 min |
| 7. Apply ConfigMap | <1 min | 40 min |
| 8. Deploy Flink Job | 5-10 min | 50 min |
| 9. Setup Monitoring | 1 min | 51 min |
| 10. Import Dashboards | 1 min | 52 min |
| 11. Deploy Producer | 2-3 min | 55 min |
| 12. Port-forward Grafana | <1 min | 55 min |
| **Total** | | **~55 min** |

---

## Troubleshooting

### Pods Not Starting

```bash
# Check node availability
kubectl get nodes

# Check pod status and events
kubectl describe pod <pod-name> -n <namespace>

# Check resource constraints
kubectl top nodes
kubectl top pods -n <namespace>
```

### Terraform Errors

```bash
# If terraform apply fails, check AWS credentials
aws sts get-caller-identity

# Check quota limits
aws service-quotas get-service-quota \
  --service-code ec2 \
  --quota-code L-1216C47A  # Running On-Demand instances
```

### Flink Job Not Starting

```bash
# Check JobManager logs
kubectl logs -n flink-benchmark -l component=jobmanager

# Check if Pulsar is accessible from Flink
kubectl exec -n flink-benchmark <jobmanager-pod> -- \
  nc -zv pulsar-proxy.pulsar.svc.cluster.local 6650

# Check if ClickHouse is accessible from Flink
kubectl exec -n flink-benchmark <jobmanager-pod> -- \
  nc -zv chi-iot-cluster-repl-iot-cluster-0-0-0.clickhouse.svc.cluster.local 8123
```

### No Data in ClickHouse

```bash
# Check if producer is running
kubectl get pods -n iot-pipeline

# Check if Pulsar has messages
kubectl exec -n pulsar pulsar-toolset-0 -- \
  bin/pulsar-admin topics stats persistent://public/default/iot-sensor-data

# Check Flink logs for errors
kubectl logs -n flink-benchmark -l component=taskmanager | grep ERROR

# Check ClickHouse connectivity
kubectl exec -n clickhouse chi-iot-cluster-repl-iot-cluster-0-0-0 -- \
  clickhouse-client --query "SELECT 1"
```

---

## Cleanup

To tear down the entire infrastructure:

```bash
# Delete Kubernetes resources first
kubectl delete namespace iot-pipeline
kubectl delete namespace flink-benchmark
kubectl delete namespace clickhouse
helm uninstall pulsar -n pulsar
kubectl delete namespace pulsar

# Then destroy Terraform infrastructure
cd /Users/vijayabhaskarv/IOT/github/RealtimeDataPlatform/aws-infra-1milion-mps
terraform destroy  # Type 'yes'
```

**Warning:** This will delete all data and cannot be undone!

---

## Performance Expectations

After successful deployment, you should see:

**Producer:**
- 250K messages/second per pod
- 750K+ messages/second total (3 pods)

**Pulsar:**
- Message rate in: 750K+ msg/sec
- Storage: Growing based on retention
- Latency: <10ms p99

**Flink:**
- Input: 750K records/second
- Output: ~12,000-15,000 aggregated records/minute (1-min windows)
- Checkpoints: Completing every 1 minute
- Backpressure: Low to none

**ClickHouse:**
- Inserts: ~200-250 records/second (aggregated data)
- Query latency: <100ms for aggregations
- Compression: 10-20x ratio
- Storage: Growing based on TTL (30 days)

---

## Next Steps

After deployment:

1. **Monitor performance** via Grafana dashboards
2. **Run benchmark queries** against ClickHouse
3. **Scale components** as needed:
   - Scale producers for more throughput
   - Scale Flink TaskManagers for more parallelism
   - Scale ClickHouse for more storage/queries
4. **Tune performance** based on metrics
5. **Set up alerting** in Grafana for critical metrics

---

## Summary

You now have a fully operational, high-throughput event streaming platform with:

✅ Real-time data ingestion (750K+ msg/sec)  
✅ Stream processing with aggregation  
✅ Persistent storage in analytics database  
✅ Complete monitoring and visualization  
✅ Fault-tolerant and scalable architecture  
✅ Multi-domain support (e-commerce, finance, IoT, gaming, logistics, etc.)  

**Use Cases:**
- E-commerce order processing and inventory management
- Financial transaction processing and fraud detection
- IoT sensor data aggregation and alerting
- Gaming event tracking and leaderboards
- Logistics package tracking and route optimization

Access your dashboards at: **http://localhost:3000** (admin/admin123)

