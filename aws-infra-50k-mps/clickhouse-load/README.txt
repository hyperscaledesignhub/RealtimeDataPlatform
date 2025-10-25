================================================================================
ClickHouse Low-Rate Data Loading Scripts
================================================================================

📊 OVERVIEW
-----------
Low-rate data generation and query benchmark scripts for ClickHouse testing.
Designed for minimal resource usage with ~25 records/sec writes and ~10 QPS queries.

📁 FILES
--------
01-create-schema.sql        - Database and table creation SQL
02-low-rate-writer.py       - Continuous data writer (25 rec/sec)
03-low-rate-benchmark.py    - Query benchmark (10 QPS)
04-deployment.yaml          - Kubernetes deployment manifests
05-deploy.sh                - Automated deployment script

⚙️ CONFIGURATION
----------------
Data Writer:
  - Target Rate: 25 records/sec (12.5 rec/sec per table)
  - Batch Size: 5 records
  - Tables: benchmark.cpu_local, benchmark.sensors_local
  - Resources: 200m CPU, 256Mi RAM (request)

Query Benchmark:
  - Target QPS: 10 queries/sec
  - Workers: 2 concurrent threads
  - Query Types: 5 different analytical queries
  - Resources: 200m CPU, 256Mi RAM (request)

🚀 QUICK START
--------------
1. Make deploy script executable:
   chmod +x 05-deploy.sh

2. Deploy everything:
   ./05-deploy.sh

3. Check writer logs:
   kubectl logs -f deployment/clickhouse-low-rate-writer

4. Verify data is being written:
   kubectl exec -n clickhouse chi-iot-cluster-repl-iot-cluster-0-0-0 -- \
     clickhouse-client --query "SELECT count() FROM benchmark.sensors_local"

📋 MANUAL DEPLOYMENT STEPS
---------------------------
1. Create ConfigMaps:
   kubectl create configmap clickhouse-low-rate-scripts \
     --from-file=create-schema.sql=01-create-schema.sql

   kubectl create configmap clickhouse-low-rate-scripts-py \
     --from-file=02-low-rate-writer.py \
     --from-file=03-low-rate-benchmark.py

2. Create Schema (Job):
   kubectl apply -f 04-deployment.yaml
   (Only the schema creation job part)

3. Deploy Writer:
   kubectl apply -f 04-deployment.yaml
   (The deployment part)

🔍 MONITORING
-------------
View writer logs:
  kubectl logs -f deployment/clickhouse-low-rate-writer

Check data counts:
  kubectl exec -n clickhouse chi-iot-cluster-repl-iot-cluster-0-0-0 -- \
    clickhouse-client --query "SELECT count() FROM benchmark.cpu_local"
  
  kubectl exec -n clickhouse chi-iot-cluster-repl-iot-cluster-0-0-0 -- \
    clickhouse-client --query "SELECT count() FROM benchmark.sensors_local"

View recent data:
  kubectl exec -n clickhouse chi-iot-cluster-repl-iot-cluster-0-0-0 -- \
    clickhouse-client --query "SELECT * FROM benchmark.sensors_local ORDER BY time DESC LIMIT 10"

🧪 RUN BENCHMARK QUERIES
-------------------------
Create and run benchmark job:
  kubectl delete job clickhouse-low-rate-benchmark --ignore-not-found=true
  
  kubectl create -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: clickhouse-low-rate-benchmark
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: benchmark
        image: python:3.9-slim
        command: ['python3', '/app/03-low-rate-benchmark.py']
        args: ['--qps=10', '--workers=2', '--duration=300']
        env:
        - name: CLICKHOUSE_HOST
          value: chi-iot-cluster-repl-iot-cluster-0-0-0.clickhouse.svc.cluster.local
        - name: CLICKHOUSE_PORT
          value: '8123'
        volumeMounts:
        - name: app
          mountPath: /app
      volumes:
      - name: app
        configMap:
          name: clickhouse-low-rate-scripts-py
          defaultMode: 0755
EOF

View benchmark results:
  kubectl logs job/clickhouse-low-rate-benchmark

⚡ CONTROL COMMANDS
-------------------
Stop writer:
  kubectl scale deployment clickhouse-low-rate-writer --replicas=0

Restart writer:
  kubectl scale deployment clickhouse-low-rate-writer --replicas=1

Delete all resources:
  kubectl delete deployment clickhouse-low-rate-writer
  kubectl delete job clickhouse-create-schema
  kubectl delete job clickhouse-low-rate-benchmark
  kubectl delete configmap clickhouse-low-rate-scripts
  kubectl delete configmap clickhouse-low-rate-scripts-py

📊 DATA MODEL (MATCHING LATEST-0 SCHEMA)
-------------
Tables Created:
  - benchmark.cpu_local      (Server CPU/memory metrics - full TSBS schema)
  - benchmark.sensors_local  (IoT device sensor readings - full schema)

CPU Table Fields (30+ fields):
  hostname, region, datacenter, rack, os, arch, team, 
  service, service_version, service_environment, time,
  usage_user, usage_system, usage_idle, usage_nice, usage_iowait,
  usage_irq, usage_softirq, usage_steal, usage_guest, usage_guest_nice,
  load1, load5, load15, n_cpus, n_users, n_processes, uptime_seconds,
  context_switches, interrupts, software_interrupts
  + total_usage (materialized: usage_user + usage_system)

Sensors Table Fields (25+ fields):
  device_id, device_type, customer_id, site_id, 
  latitude, longitude, altitude, time,
  temperature, humidity, pressure, co2_level, noise_level,
  light_level, motion_detected, battery_level, signal_strength,
  memory_usage, cpu_usage, status, error_count,
  packets_sent, packets_received, bytes_sent, bytes_received
  + has_alert (materialized: temp>35 OR humidity>80 OR battery<20)

📈 EXPECTED PERFORMANCE
-----------------------
Writer:
  - Write Rate: ~25 records/sec
  - CPU Usage: ~10-20% of 200m
  - Memory: ~100-150Mi
  - Latency: <50ms per batch

Benchmark:
  - Query Rate: ~10 QPS
  - Success Rate: >95%
  - Avg Latency: <100ms
  - P95 Latency: <200ms

🔧 CUSTOMIZATION
----------------
Adjust writer rate:
  Edit 02-low-rate-writer.py
  Change: self.target_rate = 25  # Change to desired rate

Adjust query rate:
  Edit 03-low-rate-benchmark.py
  Change: self.target_qps = 10   # Change to desired QPS

Adjust resources:
  Edit 04-deployment.yaml
  Modify resources.requests and resources.limits

🐛 TROUBLESHOOTING
------------------
Writer not starting:
  - Check ClickHouse is running: kubectl get pods -n clickhouse
  - Check configmap exists: kubectl get configmap clickhouse-low-rate-scripts-py
  - Check logs: kubectl logs deployment/clickhouse-low-rate-writer

No data in tables:
  - Check writer is running: kubectl get pods -l app=clickhouse-low-rate-writer
  - Check logs for errors: kubectl logs deployment/clickhouse-low-rate-writer
  - Verify connection: kubectl exec deployment/clickhouse-low-rate-writer -- curl chi-iot-cluster-repl-iot-cluster-0-0-0.clickhouse.svc.cluster.local:8123

Benchmark not running:
  - Check job status: kubectl get job clickhouse-low-rate-benchmark
  - Check logs: kubectl logs job/clickhouse-low-rate-benchmark
  - Verify tables have data: Run SELECT count() queries

================================================================================

