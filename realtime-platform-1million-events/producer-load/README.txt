================================================================================
IoT Data Producer - Benchmark Data Generator
================================================================================

This directory contains a high-throughput IoT data producer that generates
realistic sensor data matching the benchmark.sensors_local schema in ClickHouse.

OVERVIEW
========

The producer generates JSON messages with 25+ fields per record and publishes
them to Apache Pulsar. The messages match the exact schema used by:
  - ClickHouse table: benchmark.sensors_local
  - Flink consumer: JDBCFlinkConsumer.java

DATA MODEL
==========

Device Pool:
  - 100,000 unique device IDs (dev-0000000 to dev-0099999)
  - 10,000 customers (cust-000000 to cust-009999)
  - 1,000 sites (site-00000 to site-00999)
  - 20 device types (temperature_sensor, humidity_sensor, etc.)

Fields Generated (25+ per record):
  - Device identifiers: device_id, device_type, customer_id, site_id
  - Location: latitude, longitude, altitude
  - Timestamp: time (DateTime64(3))
  - Sensor readings: temperature, humidity, pressure, co2_level, noise_level,
    light_level, motion_detected
  - Device metrics: battery_level, signal_strength, memory_usage, cpu_usage
  - Status: status (1=online, 2=offline, 3=maintenance, 4=error), error_count
  - Network metrics: packets_sent, packets_received, bytes_sent, bytes_received

DEPLOYMENT STEPS
================

1. Build and Push Docker Image to ECR
   --------------------------------------
   ./build-and-push.sh

   This script:
   - Builds JAR using Maven
   - Creates Docker image for x86_64
   - Creates/updates ECR repository
   - Pushes image to ECR
   - Updates producer-deployment.yaml with image URL

2. Provision Infrastructure (if not already done)
   ------------------------------------------------
   cd ../
   terraform apply

   This creates 3 producer nodes (t3.medium) with label:
   workload=bench-producer

3. Deploy Producer Pods
   ---------------------
   ./deploy.sh

   This script:
   - Configures kubectl for EKS
   - Creates iot-pipeline namespace
   - Deploys 3 producer pods (1000 msg/sec each)
   - Waits for pods to be ready
   - Shows status and logs

CONFIGURATION
=============

Environment Variables:
  - PULSAR_URL: Pulsar broker URL (default: pulsar://pulsar-proxy.pulsar.svc.cluster.local:6650)
  - PULSAR_TOPIC: Topic name (default: persistent://public/default/iot-sensor-data)
  - MESSAGES_PER_SECOND: Target rate per pod (default: 1000)
  - JAVA_OPTS: JVM options (default: -Xms512m -Xmx1024m)

Scaling:
  - Horizontal: kubectl scale deployment iot-producer -n iot-pipeline --replicas=5
  - Vertical: Update MESSAGES_PER_SECOND in producer-deployment.yaml
  - Node count: Update producer_desired_size in terraform.tfvars and run terraform apply

PERFORMANCE
===========

Per-Pod Throughput:
  - Default: 1000 msg/sec
  - Max tested: 5000 msg/sec (requires higher CPU limits)

3-Pod Deployment (default):
  - Total: 3000 msg/sec
  - ~180,000 records/minute
  - ~10.8 million records/hour
  - ~259 million records/day

Resource Usage (per pod):
  - CPU: 500m (request), 1000m (limit)
  - Memory: 1Gi (request), 1.5Gi (limit)
  - Network: ~2-5 MB/sec at 1000 msg/sec

MONITORING
==========

View Producer Logs:
  kubectl logs -f -n iot-pipeline -l app=iot-producer

Check Pod Status:
  kubectl get pods -n iot-pipeline -o wide

Check Pulsar Topic Stats:
  kubectl exec -n pulsar pulsar-broker-0 -- \
    bin/pulsar-admin topics stats persistent://public/default/iot-sensor-data

Monitor Flink Ingestion:
  kubectl logs -f -n flink-benchmark deployment/iot-flink-job

Verify Data in ClickHouse:
  kubectl exec -it -n clickhouse chi-iot-cluster-repl-iot-cluster-0-0-0 -- \
    clickhouse-client --query "SELECT count(*) FROM benchmark.sensors_local"

TROUBLESHOOTING
===============

Pods Not Starting:
  - Check if producer nodes exist: kubectl get nodes -l workload=bench-producer
  - If no nodes, ensure terraform.tfvars has: producer_desired_size = 3
  - Run: terraform apply

Low Throughput:
  - Check CPU throttling: kubectl top pods -n iot-pipeline
  - Increase CPU limits in producer-deployment.yaml
  - Scale horizontally: increase replicas

Connection Errors:
  - Verify Pulsar is running: kubectl get pods -n pulsar
  - Check proxy service: kubectl get svc -n pulsar pulsar-proxy
  - Check producer logs for error details

CLEANUP
=======

Delete Producer Deployment:
  kubectl delete deployment iot-producer -n iot-pipeline

Delete Producer Infrastructure:
  Set producer_desired_size = 0 in terraform.tfvars
  terraform apply

FILES
=====

src/main/java/com/iot/pipeline/
  - model/SensorData.java       : Data model matching ClickHouse schema
  - producer/IoTDataProducer.java : Main producer class

pom.xml                    : Maven build configuration
Dockerfile                 : Multi-stage Docker build
build-and-push.sh         : Build and push to ECR
deploy.sh                 : Deploy to Kubernetes
producer-deployment.yaml  : Kubernetes deployment spec
README.txt               : This file

================================================================================

