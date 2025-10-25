# Dockerfile for Flink Consumer Job
# Force x86_64 architecture for AWS EKS compatibility (even on ARM Macs)

# Stage 1: Build the JAR using Maven
FROM --platform=linux/amd64 maven:3.9-eclipse-temurin-11 AS builder

WORKDIR /build

# Copy parent POM first for dependency resolution
COPY pom.xml .
COPY flink-consumer/pom.xml flink-consumer/

# Download dependencies (cached layer)
RUN mvn -B dependency:go-offline -f flink-consumer/pom.xml || true

# Copy source code
COPY flink-consumer/src flink-consumer/src

# Build the JAR with all dependencies
RUN mvn clean package -DskipTests -f flink-consumer/pom.xml

# Verify JAR was created
RUN ls -lh flink-consumer/target/*.jar

# Stage 2: Create runtime image
FROM --platform=linux/amd64 flink:1.18.0-java11

# Install S3 filesystem plugin for checkpointing to S3
RUN mkdir -p /opt/flink/plugins/s3-fs-hadoop && \
    cp /opt/flink/opt/flink-s3-fs-hadoop-1.18.0.jar /opt/flink/plugins/s3-fs-hadoop/ && \
    echo "Installed S3 filesystem plugin"

# Verify S3 plugin is installed
RUN ls -lh /opt/flink/plugins/s3-fs-hadoop/

# Set working directory
WORKDIR /opt/flink/usrlib

# Copy the built JAR from builder stage
COPY --from=builder /build/flink-consumer/target/flink-consumer-1.0.0.jar /opt/flink/usrlib/flink-job.jar

# Verify the JAR is present
RUN ls -lh /opt/flink/usrlib/flink-job.jar

# Set environment variables with defaults
ENV PULSAR_URL="pulsar://pulsar-proxy.pulsar.svc.cluster.local:6650"
ENV PULSAR_TOPIC="persistent://public/default/iot-sensor-data"
ENV CLICKHOUSE_URL="jdbc:clickhouse://clickhouse-iot-cluster-repl.clickhouse.svc.cluster.local:8123/benchmark"

# Metadata
LABEL maintainer="IoT Pipeline Team"
LABEL description="Flink Consumer for IoT Data Pipeline - x86_64"
LABEL version="1.0.0"
LABEL flink.version="1.18.0"

# The Flink operator will handle starting the job
# No ENTRYPOINT needed - operator manages the lifecycle

