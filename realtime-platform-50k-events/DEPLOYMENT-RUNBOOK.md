# Platform Deployment Runbook - 50K Messages/Second

This runbook provides the **exact step-by-step sequence** to deploy and run the cost-optimized event streaming platform for **50,000 messages per second**.

## Platform Overview

This platform is designed for **moderate-scale event processing** across multiple domains:
- **E-Commerce:** Order processing, inventory tracking (small-medium businesses)
- **Finance:** Transaction processing, payment events (regional operations)
- **IoT:** Sensor telemetry, device monitoring (moderate device fleet)
- **Gaming:** Player events, leaderboards (indie/mid-size games)
- **Logistics:** Package tracking, fleet management (regional logistics)
- **Social Media:** User interactions, content streams (growing platforms)

The infrastructure handles **up to 50K messages/second** with cost-optimized t3 instances.

**Cost Profile:** ~$200-250/month (with spot instances)

## Prerequisites

✅ AWS CLI configured with credentials  
✅ Terraform installed (v1.0+)  
✅ kubectl installed (v1.28+)  
✅ Docker installed  
✅ Helm installed (v3.x)

---

## Deployment Sequence

### Step 1: Deploy Infrastructure with Terraform

Create the AWS infrastructure (VPC, EKS cluster, cost-optimized node groups).

```bash
# Navigate to infrastructure directory
cd /Users/vijayabhaskarv/IOT/github/RealtimeDataPlatform/realtime-platform-50k-events

# Initialize Terraform (downloads providers and modules)
terraform init

# Review what will be created
terraform plan

# Deploy infrastructure (creates VPC, EKS, t3 instance node groups)
terraform apply
# Type 'yes' when prompted

# Wait for completion (~15-20 minutes)
```

**What this creates:**
- VPC with public and private subnets
- EKS cluster (bench-low-infra)
- 7 cost-optimized node groups with t3 instances:
  - Producer: t3.medium (1-3 nodes)
  - Pulsar ZK: t3.small (3 nodes)
  - Pulsar Broker: t3.large (2-4 nodes)
  - Flink JM: t3.large (1 node)
  - Flink TM: t3.large (1-2 nodes)
  - ClickHouse: t3.xlarge (2-4 nodes)
  - General: t3.small (1-2 nodes)
- S3 bucket for Flink state
- IAM roles and policies
- ECR repositories

**Cost Optimization:**
- Uses t3 instances (burstable, cost-effective)
- EBS gp3 storage (no expensive NVMe)
- Spot instances supported
- Single AZ deployment option

**Verify:**
```bash
# Configure kubectl
aws eks update-kubeconfig --region us-west-2 --name bench-low-infra

# Check cluster is accessible
kubectl get nodes

# You should see t3.* instances in Ready state
```

---

### Step 2: Deploy Pulsar

Deploy Apache Pulsar message broker with EBS storage (cost-optimized).

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
- Pulsar cluster using Helm chart:
  - ZooKeeper: 3 nodes (t3.small)
  - Broker: 2-4 nodes (t3.large)
  - BookKeeper: 2-4 nodes with EBS storage (t3.large)
  - Proxy: 1-2 nodes (t3.medium)
  - Toolset: 1 pod (admin utilities)

**Configuration:**
- Storage: EBS gp3 (no NVMe for cost savings)
- Capacity: 50K messages/second
- Retention: 7 days
- Replication: 2-3 replicas

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

Deploy ClickHouse database cluster with EBS storage.

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
- ClickHouse cluster: 2-4 replicas (t3.xlarge)
- EBS gp3 storage (200 GB per node)
- Moderate query performance optimization

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

Create database tables optimized for moderate data volumes.

```bash
# Still in clickhouse-load directory

# Create schema on all replicas
./00-create-schema-all-replicas.sh
```

**What this creates:**
- Database: `benchmark`
- Table: `benchmark.sensors_local` (25 fields)
- Table: `benchmark.cpu_local` (30+ fields)
- Materialized columns
- Replication: 2 replicas
- TTL: 30 days (auto-cleanup)

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

Install Flink Kubernetes Operator for job management.

```bash
# Navigate to Flink directory
cd ../flink-load

# Deploy Flink Operator
./deploy.sh

# Wait for operator to be ready (~2-3 minutes)
kubectl get pods -n flink-operator -w
# Press Ctrl+C when operator pod is Running
```

**What this deploys:**
- cert-manager (if not already installed)
- Flink Kubernetes Operator v1.7.0
- Custom Resource Definitions (FlinkDeployment)

**Verify:**
```bash
# Check Flink Operator is running
kubectl get pods -n flink-operator

# Check CRDs are installed
kubectl get crd | grep flink
```

---

### Step 6: Setup S3 for Flink Checkpoints

Configure S3 as checkpoint storage backend.

```bash
# Still in flink-load directory

# Setup S3 checkpoint configuration
./setup-s3-checkpoints.sh
```

**What this does:**
- Configures S3 bucket for checkpoints
- Sets up IAM permissions
- 7-day lifecycle policy for cost control

**Verify:**
```bash
# Check S3 bucket exists
aws s3 ls | grep flink-state

# Check secrets (if any)
kubectl get secrets -n flink-benchmark
```

---

### Step 7: Apply Flink ConfigMap

Create ConfigMap with Flink configuration.

```bash
# Still in flink-load directory

# Apply Flink configuration ConfigMap
kubectl apply -f flink-config-configmap.yaml -n flink-benchmark

# Verify ConfigMap
kubectl get configmap -n flink-benchmark
kubectl describe configmap flink-config -n flink-benchmark
```

---

### Step 8: Deploy Flink Job

Deploy the Flink streaming job (cost-optimized configuration).

```bash
# Still in flink-load directory

# Build and push Flink job image to ECR
./build-and-push.sh

# Deploy Flink job using FlinkDeployment CRD
kubectl apply -f flink-job-deployment.yaml

# Wait for Flink pods to start (~2-3 minutes)
kubectl get pods -n flink-benchmark -w
# Press Ctrl+C when JobManager and TaskManagers are Running
```

**What this deploys:**
- JobManager: 1 pod (t3.large, 4 GB RAM)
- TaskManager: 1-2 pods (t3.large, 4 GB RAM each)
- Parallelism: 2-4 task slots
- Processing capacity: 50K msg/sec input

**Verify:**
```bash
# Check Flink deployment status
kubectl get flinkdeployment -n flink-benchmark

# Check Flink pods
kubectl get pods -n flink-benchmark

# Check JobManager logs
kubectl logs -n flink-benchmark -l component=jobmanager

# Check TaskManager logs
kubectl logs -n flink-benchmark -l component=taskmanager
```

---

### Step 9: Setup Flink Monitoring

Enable Prometheus metrics collection for Flink.

```bash
# Still in flink-load directory

# Setup Flink metrics monitoring
./setup-flink-metrics.sh

# Start monitoring
./monitor-flink.sh
```

**What this does:**
- Configures Prometheus ServiceMonitor
- Exposes Flink metrics endpoint
- Sets up metric collection

**Verify:**
```bash
# Check ServiceMonitor
kubectl get servicemonitor -n flink-benchmark

# Check metrics endpoint
kubectl port-forward -n flink-benchmark <jobmanager-pod> 9249:9249 &
curl http://localhost:9249/metrics
```

---

### Step 10: Import Grafana Dashboards

Import pre-configured dashboards for all components.

```bash
# Navigate to Grafana dashboards directory
cd ../grafana-dashboards

# Import all dashboards
./import-dashboards.sh
```

**What this imports:**
- Pulsar dashboard (broker metrics, topic stats)
- Flink dashboard (job metrics, checkpoints)
- ClickHouse dashboard (query performance, storage)

**Verify:**
```bash
# Check Grafana pod is running
kubectl get pods -n pulsar | grep grafana
```

---

### Step 11: Deploy Event Producer

Deploy the event producer (scaled for 50K msg/sec).

```bash
# Navigate to Producer directory
cd ../producer-load

# Build and push producer image to ECR
./build-and-push.sh

# Deploy producer (configured for 500-1K msg/sec per pod)
./deploy.sh
```

**What this deploys:**
- Producer pods: 1-3 instances (t3.medium)
- Each pod: 500-1,000 messages/second
- Total throughput: 500-3,000 messages/second
- Scalable to 50K by increasing replicas
- AVRO-encoded event messages

**Configuration:**
- Instance: t3.medium (2 vCPU, 4 GB RAM)
- Rate: 500-1K msg/sec per pod
- Event sources: 10,000 unique IDs
- Adaptable for any domain

**Verify:**
```bash
# Check producer pods are running
kubectl get pods -n iot-pipeline

# Check producer logs
kubectl logs -f -n iot-pipeline -l app=iot-producer

# You should see messages like:
# "Sent 1000 messages in last second"
```

**Scale to 50K msg/sec:**
```bash
# Scale to handle full 50K load
kubectl scale deployment iot-producer -n iot-pipeline --replicas=50

# Or increase rate per pod
kubectl set env deployment/iot-producer -n iot-pipeline MESSAGES_PER_SECOND=1000
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

1. Left menu → **"Dashboards"** (four squares icon)
2. Search: **"Pulsar"**
3. Click **"Apache Pulsar Dashboard"**

**Metrics visible:**
- Broker throughput (msg/sec)
- Topic statistics
- Storage size (EBS)
- Producer/consumer connections
- Backlog size

#### View ClickHouse Metrics

1. Left menu → **"Dashboards"**
2. Search: **"ClickHouse"**
3. Click **"ClickHouse Dashboard"**

**Metrics visible:**
- Query execution time
- Rows read/written per second
- Table sizes and compression
- Memory usage
- INSERT/SELECT queries per second

#### View Flink Metrics

1. Left menu → **"Dashboards"**
2. Search: **"Flink"**
3. Click **"Apache Flink Dashboard"**

**Metrics visible:**
- Records processed per second
- Checkpoint duration
- Task backpressure
- Memory usage (heap/non-heap)
- Watermark lag

---

## Complete Command Reference

Here's the complete sequence for easy copy-paste:

```bash
# ============================================================================
# COMPLETE DEPLOYMENT SEQUENCE - 50K Messages/Second
# ============================================================================

# Step 1: Deploy Infrastructure
cd /Users/vijayabhaskarv/IOT/github/RealtimeDataPlatform/realtime-platform-50k-events
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
./deploy.sh
kubectl get pods -n iot-pipeline -w  # Wait until all Running

# Step 12: Port-forward Grafana
kubectl port-forward -n pulsar svc/grafana 3000:3000

# Step 13: Access Grafana
# Open browser: http://localhost:3000
# Login: admin / admin123
```

---

## Verification Commands

After deployment, verify the system is working:

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

# 6. Check resource usage
kubectl top nodes
kubectl top pods --all-namespaces
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
| 8. Deploy Flink Job | 3-5 min | 45 min |
| 9. Setup Monitoring | 1 min | 46 min |
| 10. Import Dashboards | 1 min | 47 min |
| 11. Deploy Producer | 2-3 min | 50 min |
| 12. Port-forward Grafana | <1 min | 50 min |
| **Total** | | **~50 min** |

---

## Scaling Operations

### Scale to Handle More Load

**Current: ~1K msg/sec → Target: 10K msg/sec**
```bash
kubectl scale deployment iot-producer -n iot-pipeline --replicas=10
```

**Current: ~10K msg/sec → Target: 30K msg/sec**
```bash
# Scale producer
kubectl scale deployment iot-producer -n iot-pipeline --replicas=30

# Scale Flink TaskManagers
kubectl patch flinkdeployment iot-flink-job -n flink-benchmark \
  --type merge -p '{"spec":{"taskManager":{"replicas":2}}}'
```

**Current: ~30K msg/sec → Target: 50K msg/sec**
```bash
# Scale producer
kubectl scale deployment iot-producer -n iot-pipeline --replicas=50

# Scale Flink
kubectl patch flinkdeployment iot-flink-job -n flink-benchmark \
  --type merge -p '{"spec":{"taskManager":{"replicas":3}}}'

# Add Pulsar brokers (via Terraform)
# Update terraform.tfvars: pulsar_broker_desired_size = 4
terraform apply
```

### Scale Down to Reduce Costs

**From 50K → 10K msg/sec:**
```bash
kubectl scale deployment iot-producer -n iot-pipeline --replicas=10
kubectl patch flinkdeployment iot-flink-job -n flink-benchmark \
  --type merge -p '{"spec":{"taskManager":{"replicas":1}}}'
```

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

### Low Throughput

```bash
# Check CPU throttling
kubectl top pods -n <namespace>

# Check producer rate
kubectl logs -n iot-pipeline -l app=iot-producer | tail -20

# Increase producer replicas
kubectl scale deployment iot-producer -n iot-pipeline --replicas=5
```

### Flink Job Not Processing

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
cd /Users/vijayabhaskarv/IOT/github/RealtimeDataPlatform/realtime-platform-50k-events
terraform destroy  # Type 'yes'
```

**Warning:** This will delete all data and cannot be undone!

---

## Performance Expectations

After successful deployment:

**Producer:**
- 500-1,000 messages/second per pod
- Scalable to 50K+ by adding replicas

**Pulsar:**
- Message rate in: Up to 50K msg/sec
- Storage: EBS gp3 (cost-effective)
- Latency: <20ms p99

**Flink:**
- Input: Up to 50K records/second
- Output: ~800-1,000 aggregated records/minute
- Checkpoints: Completing every 1 minute
- Backpressure: Low to none

**ClickHouse:**
- Inserts: ~15-20 records/second (aggregated data)
- Query latency: <200ms for aggregations
- Compression: 10-20x ratio
- Storage: EBS gp3

---

## Cost Monitoring

**Monthly Cost Breakdown:**
- Compute (t3 instances): ~$150-200
- EBS Storage: ~$40
- S3 Storage: ~$1
- NAT Gateway: ~$32
- Data Transfer: ~$20
- **Total: ~$200-250/month** (with spot instances)

**Cost Optimization Tips:**
1. Use spot instances (60-70% savings)
2. Scale down during off-hours
3. Set S3 lifecycle policies
4. Monitor unused resources
5. Right-size based on actual usage

---

## Next Steps

After deployment:

1. **Monitor performance** via Grafana dashboards
2. **Scale as needed** based on actual load
3. **Tune performance** based on metrics
4. **Set up alerting** in Grafana
5. **Plan capacity** for growth

---

## Upgrade to 1M Setup

If you need higher throughput (250K+ msg/sec):

1. See `../realtime-platform-1million-events/` for high-scale configuration
2. Main differences:
   - Larger instances (c5/r6id vs t3)
   - NVMe storage (vs EBS)
   - More replicas
   - Cost: ~$3,500/month vs $200/month
3. Migration guide available in 1M deployment runbook

---

## Summary

You now have a fully operational, **cost-optimized** event streaming platform with:

✅ Moderate throughput (up to 50K msg/sec)  
✅ Low cost (~$200-250/month)  
✅ Stream processing with aggregation  
✅ Persistent storage in analytics database  
✅ Complete monitoring and visualization  
✅ Scalable architecture (can grow to 1M setup)  
✅ Multi-domain support (e-commerce, finance, IoT, gaming, logistics)  

**Access dashboards:** http://localhost:3000 (admin/admin123)

**Perfect for:**
- Development and testing environments
- Small to medium workloads
- Cost-conscious deployments
- Proof of concept projects
- Growing platforms that may scale later

