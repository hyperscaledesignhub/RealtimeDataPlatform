================================================================================
FLINK DEPLOYMENT GUIDE - Low Infra
================================================================================

OVERVIEW:
---------
This folder contains everything needed to deploy Flink jobs on EKS that:
  - Consume IoT sensor data from Pulsar
  - Process and transform data
  - Write to ClickHouse (benchmark.sensors_local table)

================================================================================
HOW FLINK KUBERNETES OPERATOR WORKS
================================================================================

Architecture:
-------------
1. Flink Operator (running in flink-operator namespace)
2. FlinkDeployment CRD (defines your job)
3. Operator creates:
   └─> JobManager Pod (1 replica) - Job coordination
   └─> TaskManager Pods (N replicas) - Parallel execution

When you apply flink-job-deployment.yaml:
  FlinkDeployment → Operator → JobManager + TaskManagers automatically created

================================================================================
FILES IN THIS FOLDER
================================================================================

deploy.sh                   - Install Flink Kubernetes Operator
build-and-push.sh           - Build Docker image (x86) and push to ECR
Dockerfile                  - Multi-stage build for Flink job
flink-job-deployment.yaml   - FlinkDeployment manifest to run the job
flink-consumer/             - Java source code (updated for benchmark schema)
pom.xml                     - Maven parent POM
SCHEMA_COMPARISON.txt       - Schema documentation
README.txt                  - This file

================================================================================
DEPLOYMENT STEPS
================================================================================

STEP 1: Install Flink Operator
-------------------------------
cd /Users/vijayabhaskarv/IOT/datapipeline-0/Flink-Benchmark/low_infra_flink/flink-load

./deploy.sh

This installs:
  - cert-manager (for webhooks)
  - Flink Kubernetes Operator v1.13.0

Verify:
  kubectl get pods -n flink-operator
  kubectl get pods -n cert-manager


STEP 2: Build and Push Docker Image
------------------------------------
# Update AWS account ID in flink-job-deployment.yaml first
# Get account ID:
aws sts get-caller-identity --query Account --output text

# Build and push
./build-and-push.sh

This will:
  - Build JAR using Maven
  - Create Docker image for linux/amd64 (x86_64)
  - Push to ECR: bench-low-infra-flink-job

Build time: ~5-10 minutes (first time)

Verify:
  aws ecr describe-images --repository-name bench-low-infra-flink-job --region us-west-2


STEP 3: Update Image URL in Deployment YAML
--------------------------------------------
Edit flink-job-deployment.yaml:
  Line 9: Update with your AWS account ID
  
  spec:
    image: <YOUR-ACCOUNT-ID>.dkr.ecr.us-west-2.amazonaws.com/bench-low-infra-flink-job:latest


STEP 4: Deploy Flink Job
-------------------------
kubectl apply -f flink-job-deployment.yaml

The Flink Operator will automatically create:
  - 1 JobManager pod
  - 2 TaskManager pods

Verify:
  kubectl get flinkdeployment -n flink-benchmark
  kubectl get pods -n flink-benchmark


STEP 5: Monitor the Job
------------------------
# Watch pods being created
kubectl get pods -n flink-benchmark -w

# Check JobManager logs
kubectl logs -n flink-benchmark <jobmanager-pod-name>

# Check TaskManager logs
kubectl logs -n flink-benchmark <taskmanager-pod-name>

# Check Flink deployment status
kubectl describe flinkdeployment iot-flink-job -n flink-benchmark


================================================================================
ARCHITECTURE
================================================================================

Data Flow:
----------
IoT Devices → Pulsar → Flink (JobManager + TaskManagers) → ClickHouse

Pulsar Connection:
  pulsar://pulsar-proxy.pulsar.svc.cluster.local:6650
  Topic: persistent://public/default/iot-sensor-data

ClickHouse Connection:
  jdbc:clickhouse://clickhouse-iot-cluster-repl.clickhouse.svc.cluster.local:8123/benchmark
  Table: benchmark.sensors_local

Pod Placement:
--------------
JobManager:  
  - Node: Flink JobManager nodes (t3.medium)
  - Label: workload=flink, component=jobmanager
  - Resource: 2GB RAM, 1 CPU

TaskManager: 
  - Nodes: Flink TaskManager nodes (t3.medium)
  - Label: workload=flink, component=taskmanager
  - Replicas: 2
  - Resource: 2GB RAM, 1 CPU each
  - Task Slots: 2 per TaskManager

================================================================================
SCHEMA MAPPING
================================================================================

The Flink consumer now writes to: benchmark.sensors_local

Fields (25 total):
  device_id, device_type, customer_id, site_id
  latitude, longitude, altitude, time
  temperature, humidity, pressure, co2_level, noise_level, light_level, motion_detected
  battery_level, signal_strength, memory_usage, cpu_usage
  status, error_count
  packets_sent, packets_received, bytes_sent, bytes_received

Backward Compatibility:
  - Accepts old field names (sensorId → device_id)
  - Provides defaults for missing fields
  - Converts status string to int (online=1, offline=2, etc.)

================================================================================
TROUBLESHOOTING
================================================================================

JobManager Not Starting:
------------------------
Issue: Pod stuck in Pending
Check:
  kubectl describe pod -n flink-benchmark <jobmanager-pod>
  
Common causes:
  - No Flink JobManager nodes available
  - Insufficient resources
  - Node selector mismatch

Solution:
  # Check Flink nodes exist
  kubectl get nodes -l workload=flink
  
  # Scale JobManager nodes if needed
  aws autoscaling set-desired-capacity --region us-west-2 \
    --auto-scaling-group-name <jobmanager-asg-name> --desired-capacity 1


Image Pull Errors:
------------------
Issue: ErrImagePull or ImagePullBackOff
Check:
  kubectl describe pod -n flink-benchmark <pod-name>

Solution:
  # Verify ECR image exists
  aws ecr describe-images --repository-name bench-low-infra-flink-job --region us-west-2
  
  # Re-push image
  cd flink-load
  ./build-and-push.sh


Job Failing:
------------
Issue: Job restarts or fails
Check logs:
  kubectl logs -n flink-benchmark <jobmanager-pod>

Common issues:
  - Pulsar not reachable
  - ClickHouse not reachable
  - Schema mismatch
  - No data in Pulsar topic

Solution:
  # Test Pulsar connection
  kubectl -n pulsar exec -it pulsar-toolset-0 -- bin/pulsar-admin topics stats persistent://public/default/iot-sensor-data
  
  # Test ClickHouse connection
  kubectl exec -n clickhouse chi-iot-cluster-repl-iot-cluster-0-0-0 -- clickhouse-client --query "SELECT 1"


No Data in ClickHouse:
----------------------
Issue: Flink running but no data written
Check:
  # Verify data in Pulsar topic
  kubectl -n pulsar exec -it pulsar-toolset-0 -- \
    bin/pulsar-client consume persistent://public/default/iot-sensor-data -s test-sub -n 10
  
  # Check Flink logs for errors
  kubectl logs -n flink-benchmark <taskmanager-pod> | grep -i "error\|exception"
  
  # Verify ClickHouse table exists
  kubectl exec -n clickhouse chi-iot-cluster-repl-iot-cluster-0-0-0 -- \
    clickhouse-client --query "SHOW TABLES FROM benchmark"

================================================================================
OPERATIONAL COMMANDS
================================================================================

Start Job:
----------
kubectl apply -f flink-job-deployment.yaml

Stop Job:
---------
kubectl patch flinkdeployment iot-flink-job -n flink-benchmark \
  --type merge -p '{"spec":{"job":{"state":"suspended"}}}'

Resume Job:
-----------
kubectl patch flinkdeployment iot-flink-job -n flink-benchmark \
  --type merge -p '{"spec":{"job":{"state":"running"}}}'

Delete Job:
-----------
kubectl delete flinkdeployment iot-flink-job -n flink-benchmark

Scale TaskManagers:
-------------------
kubectl patch flinkdeployment iot-flink-job -n flink-benchmark \
  --type merge -p '{"spec":{"taskManager":{"replicas":4}}}'

Trigger Savepoint:
------------------
kubectl patch flinkdeployment iot-flink-job -n flink-benchmark \
  --type merge -p '{"spec":{"job":{"savepointTriggerNonce":1}}}'

View Savepoints:
----------------
aws s3 ls s3://bench-low-infra-flink-state-343218179954/savepoints/ --recursive

================================================================================
MONITORING
================================================================================

Check Job Status:
-----------------
kubectl get flinkdeployment -n flink-benchmark
kubectl describe flinkdeployment iot-flink-job -n flink-benchmark

View All Flink Pods:
--------------------
kubectl get pods -n flink-benchmark -l app=iot-flink-job

Resource Usage:
---------------
kubectl top pods -n flink-benchmark

Flink Web UI (Port Forward):
-----------------------------
# Forward JobManager web UI
kubectl port-forward -n flink-benchmark <jobmanager-pod> 8081:8081

# Access at: http://localhost:8081

================================================================================
UPDATING THE JOB
================================================================================

To update the Flink job code:

1. Modify Java code in flink-consumer/src/
2. Rebuild and push:
   ./build-and-push.sh
3. Update FlinkDeployment (triggers rolling update):
   kubectl patch flinkdeployment iot-flink-job -n flink-benchmark \
     --type merge -p '{"spec":{"job":{"state":"suspended"}}}'
   
   # Wait for job to stop
   sleep 30
   
   kubectl patch flinkdeployment iot-flink-job -n flink-benchmark \
     --type merge -p '{"spec":{"job":{"state":"running"}}}'

Or delete and recreate:
   kubectl delete flinkdeployment iot-flink-job -n flink-benchmark
   kubectl apply -f flink-job-deployment.yaml

================================================================================
CLEANUP
================================================================================

Delete Flink Job:
-----------------
kubectl delete flinkdeployment iot-flink-job -n flink-benchmark

Uninstall Flink Operator:
--------------------------
helm uninstall flink-kubernetes-operator -n flink-operator
kubectl delete namespace flink-operator

Delete cert-manager:
--------------------
helm uninstall cert-manager -n cert-manager
kubectl delete namespace cert-manager

================================================================================
CONFIGURATION
================================================================================

Environment Variables (configured in flink-job-deployment.yaml):
-----------------------------------------------------------------
PULSAR_URL:       pulsar://pulsar-proxy.pulsar.svc.cluster.local:6650
PULSAR_TOPIC:     persistent://public/default/iot-sensor-data
CLICKHOUSE_URL:   jdbc:clickhouse://clickhouse-iot-cluster-repl.clickhouse.svc.cluster.local:8123/benchmark

To change these, edit flink-job-deployment.yaml and reapply.

S3 State Backend:
-----------------
Checkpoints: s3://bench-low-infra-flink-state-343218179954/checkpoints
Savepoints:  s3://bench-low-infra-flink-state-343218179954/savepoints

Configured for exactly-once processing with 1-minute checkpoints.

================================================================================
RESOURCE ALLOCATION
================================================================================

Current Configuration:
----------------------
JobManager:    1 replica  × 2GB RAM × 1 CPU   = 2GB RAM, 1 CPU total
TaskManager:   2 replicas × 2GB RAM × 1 CPU   = 4GB RAM, 2 CPU total
               2 task slots per TM              = 4 task slots total

Total: 6GB RAM, 3 CPU for Flink cluster

Scaling Recommendations:
------------------------
For higher throughput:
  - Increase TaskManager replicas (more parallelism)
  - Increase task slots per TaskManager
  - Add more memory/CPU per pod

Example scaling to 4 TaskManagers:
  kubectl patch flinkdeployment iot-flink-job -n flink-benchmark \
    --type merge -p '{"spec":{"taskManager":{"replicas":4}}}'

================================================================================
END OF GUIDE
================================================================================

