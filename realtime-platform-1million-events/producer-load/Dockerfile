# ================================================================================
# Multi-stage Dockerfile for IoT Data Producer
# Builds JAR and creates optimized runtime image for x86_64
# ================================================================================

# Stage 1: Build the JAR
FROM --platform=linux/amd64 maven:3.9-eclipse-temurin-11 AS builder

WORKDIR /build

# Copy pom.xml and download dependencies (cached layer)
COPY pom.xml .
RUN mvn dependency:go-offline -B

# Copy source code and build
COPY src ./src
RUN mvn clean package -DskipTests -B

# Verify JAR was created
RUN ls -lh /build/target/*.jar

# Stage 2: Create runtime image
FROM --platform=linux/amd64 eclipse-temurin:11-jre-alpine

# Install bash for better container debugging
RUN apk add --no-cache bash

# Create app directory
WORKDIR /app

# Copy JAR from builder
COPY --from=builder /build/target/iot-producer.jar /app/iot-producer.jar

# Set default environment variables
ENV PULSAR_URL="pulsar://localhost:6650" \
    PULSAR_TOPIC="persistent://public/default/iot-sensor-data" \
    MESSAGES_PER_SECOND="1000" \
    JAVA_OPTS="-Xms512m -Xmx1024m"

# Run the producer
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar /app/iot-producer.jar"]

