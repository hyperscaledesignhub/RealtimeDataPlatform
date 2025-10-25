# Producer Build Approach - Multi-Stage Docker Build

## Overview
We use a **multi-stage Docker build** that downloads Pulsar source, builds only the testclient module with our custom `IoTPerformanceProducer`, and creates a clean runtime image.

## ✅ Benefits of This Approach

1. **Clean Repository**: No JAR files checked into Git
2. **Reproducible Builds**: Always builds from official Pulsar 4.1.1 source
3. **Smaller Git Repo**: Only source files are tracked
4. **Easy Updates**: Change Pulsar version by updating one line
5. **Standard Maven Practice**: Dependencies downloaded automatically

## 📦 Required Files in Repository

```
producer-load/
├── IoTPerformanceProducer.java    # Custom producer implementation
├── pulsar-sensor-perf             # Wrapper script to run the producer
├── Dockerfile.perf                # Multi-stage build definition
├── entrypoint.sh                  # Device ID distribution logic
└── src/main/resources/avro/       # AVRO schemas (optional)
```

## 🏗️ Build Process

### Stage 1: Builder
1. Download Apache Pulsar 4.1.1 source (`~150MB`)
2. Copy `IoTPerformanceProducer.java` into source tree
3. Build **only** `pulsar-testclient` module with Maven
4. Generate `pulsar-testclient.jar` + all dependencies

### Stage 2: Runtime
1. Use lightweight JRE image
2. Copy built artifacts from Stage 1:
   - `pulsar-testclient.jar`
   - `dependency/*.jar` (~366 JARs)
3. Copy `pulsar-sensor-perf` script
4. Copy `entrypoint.sh` for device ID distribution
5. Configure environment variables

## 🚀 Building the Docker Image

### Local Build
```bash
cd realtime-platform-1million-events/producer-load
docker build -f Dockerfile.perf -t iot-producer-perf:latest .
```

### Using Build Script
```bash
./build-and-push-perf.sh
```

This will:
- Build the multi-stage image
- Push to ECR
- Update deployment YAML with correct image URL

## ⏱️ Build Time

- **First build**: ~10-15 minutes (downloads source + dependencies)
- **Subsequent builds**: ~5-8 minutes (Docker layer caching)
- **If only IoTPerformanceProducer.java changes**: ~2-3 minutes

## 🎯 What Gets Built

### pulsar-testclient Module
```
pulsar-testclient/
├── target/
│   ├── pulsar-testclient-4.1.1.jar    # Main JAR with our custom class
│   └── dependency/                     # All Maven dependencies
│       ├── pulsar-client-*.jar
│       ├── netty-*.jar
│       ├── avro-*.jar
│       └── ... (~366 JARs total)
```

## 📝 IoTPerformanceProducer.java

This is our **custom** Pulsar producer that:
- Extends Apache Pulsar's testclient framework
- Generates synthetic IoT sensor data
- Supports AVRO serialization
- Distributes device IDs across multiple pods
- Implements rate limiting and batching

**Package**: `org.apache.pulsar.testclient.IoTPerformanceProducer`

## 🔧 pulsar-sensor-perf Script

Custom wrapper script that:
- Sets up Java classpath with all dependencies
- Configures JVM options for Java 11+, 17+, 23+
- Enables Netty reflection access
- Configures logging
- Calls `org.apache.pulsar.testclient.IoTPerformanceProducer`

## 🌍 Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PULSAR_URL` | `pulsar://localhost:6650` | Pulsar broker URL |
| `PULSAR_TOPIC` | `persistent://public/default/iot-sensor-data` | Target topic |
| `MESSAGE_RATE` | `250000` | Messages/second per pod |
| `TOTAL_DEVICE_COUNT` | `100000` | Total unique device IDs |
| `NUM_REPLICAS` | `3` | Number of producer pods |
| `USE_AVRO` | `true` | Enable AVRO serialization |
| `JAVA_OPTS` | `-Xms512m -Xmx1024m -XX:+UseG1GC` | JVM options |

## 🔄 Updating Pulsar Version

To use a different Pulsar version, edit `Dockerfile.perf`:

```dockerfile
# Change this line:
wget https://archive.apache.org/dist/pulsar/pulsar-4.1.1/apache-pulsar-4.1.1-src.tar.gz

# To (example):
wget https://archive.apache.org/dist/pulsar/pulsar-4.2.0/apache-pulsar-4.2.0-src.tar.gz
```

## 🐛 Troubleshooting

### Build Fails - Maven Errors
```bash
# Check Pulsar source was downloaded correctly
docker build --target builder -f Dockerfile.perf -t test-builder .
docker run -it test-builder ls -la /build/pulsar-src
```

### Runtime - JAR Not Found
```bash
# Verify artifacts were copied
docker run -it iot-producer-perf:latest ls -la /app/target/
```

### Class Not Found Error
```bash
# Check IoTPerformanceProducer is in the JAR
docker run -it iot-producer-perf:latest jar tf /app/target/pulsar-testclient.jar | grep IoTPerformanceProducer
```

## 📊 Docker Image Size

- **Builder stage**: ~2.5GB (discarded)
- **Final runtime image**: ~800MB-1GB
  - Base JRE: ~200MB
  - Dependencies: ~600MB
  - Runtime overhead: ~100MB

## 🔐 Security

- Runs as non-root user (`appuser:1001`)
- Minimal Alpine-based JRE image
- No unnecessary tools in runtime image
- Healthcheck monitors process

## 📚 References

- [Apache Pulsar Documentation](https://pulsar.apache.org/docs/next/)
- [Pulsar Performance Tools](https://pulsar.apache.org/docs/next/performance-tools/)
- [Multi-Stage Docker Builds](https://docs.docker.com/build/building/multi-stage/)

