# RealtimeDataPlatform

A comprehensive event streaming platform designed for high-throughput, real-time data processing across multiple domains including e-commerce, finance, IoT, gaming, logistics, and social media.

## 🏗️ Platform Architecture

![Scaling 1 Million Events](docs/Scaling%201%20million%20events.png)

## 📁 Repository Structure

### 🚀 Production Deployments

#### `realtime-platform-1million-events/` - High-Scale Production Setup
- **Purpose**: Enterprise-grade infrastructure for 1 million messages/second
- **Components**: 
  - **Flink Load**: Real-time stream processing with AVRO deserialization
  - **Pulsar Load**: Distributed messaging and streaming platform
  - **ClickHouse Load**: Columnar database for analytical queries
  - **Producer Load**: High-throughput event data generation
- **Infrastructure**: AWS EKS, dedicated node groups, NVMe storage
- **Cost**: $24,592/month
- **Documentation**: [Complete 1M MPS Documentation](realtime-platform-1million-events/README.md)

#### `realtime-platform-50k-events/` - Cost-Optimized Production Setup
- **Purpose**: Cost-effective infrastructure for 50,000 messages/second
- **Components**: Same as 1M MPS but with smaller instance types
- **Infrastructure**: AWS EKS with t3 series instances, EBS gp3 storage
- **Cost**: ~$200-250/month
- **Documentation**: [Complete 50K MPS Documentation](realtime-platform-50k-events/README.md)

### 🛠️ Development Environment

#### `local-setup/` - Local Development Environment
- **Purpose**: Local development and testing environment
- **Components**: Docker Compose + Kubernetes (Kind) setup
- **Services**: Pulsar, Flink, ClickHouse, Producer
- **Quick Start**: 
  ```bash
  cd local-setup
  ./scripts/start-pipeline.sh  # Start all services
  ./scripts/stop-pipeline.sh   # Stop all services
  ```
- **Documentation**: [Local Setup Guide](local-setup/README.md)

## 🎯 Platform Components

### 1. **Event Producers** (`producer-load/`)
- **Purpose**: Generate high-volume event streams
- **Technology**: Java-based AVRO serialization
- **Features**: 
  - 100,000 unique device IDs (1M MPS) / 10,000 event sources (50K MPS)
  - Scalable Kubernetes deployment
  - Multi-domain event generation

### 2. **Message Streaming** (`pulsar-load/`)
- **Purpose**: Reliable message ingestion and distribution
- **Technology**: Apache Pulsar with Helm deployment
- **Features**:
  - Distributed messaging with NVMe storage
  - AVRO schema support
  - High availability and fault tolerance

### 3. **Stream Processing** (`flink-load/`)
- **Purpose**: Real-time data transformation and aggregation
- **Technology**: Apache Flink with JDBC sink
- **Features**:
  - AVRO deserialization (`JDBCFlinkConsumer.java`)
  - 1-minute window aggregations
  - Checkpoint-aware batched writes to ClickHouse

### 4. **Analytical Storage** (`clickhouse-load/`)
- **Purpose**: High-performance analytical database
- **Technology**: ClickHouse with optimized schemas
- **Features**:
  - Columnar storage for time-series data
  - Real-time query capabilities
  - Optimized for analytical workloads

### 5. **Monitoring & Observability** (`grafana-dashboards/`)
- **Purpose**: Platform monitoring and metrics visualization
- **Technology**: Grafana with custom dashboards
- **Features**:
  - Flink job monitoring
  - ClickHouse performance metrics
  - Pulsar cluster health

## 🚀 Quick Start Guide

### For Local Development
```bash
cd local-setup
./scripts/start-pipeline.sh
# Access services at localhost:3000 (Grafana)
```

### For Production Deployment
1. **1M MPS Setup**: Follow [1M MPS Deployment Guide](realtime-platform-1million-events/DEPLOYMENT-RUNBOOK.md)
2. **50K MPS Setup**: Follow [50K MPS Deployment Guide](realtime-platform-50k-events/DEPLOYMENT-RUNBOOK.md)

## 📊 Performance Characteristics

| Setup | Throughput | Cost/Month | Use Case |
|-------|------------|------------|----------|
| Local | ~1K msg/sec | Free | Development |
| 50K MPS | 50,000 msg/sec | $200-250 | Small-Medium Business |
| 1M MPS | 1,000,000 msg/sec | $24,592 | Enterprise |

## 🎯 Supported Domains

- **E-commerce**: Order processing, inventory management, recommendation engines
- **Finance**: Trading data, fraud detection, risk analysis
- **IoT**: Sensor data, device monitoring, predictive maintenance
- **Gaming**: Player analytics, real-time leaderboards, event processing
- **Logistics**: Package tracking, route optimization, supply chain analytics
- **Social Media**: Content processing, engagement metrics, trend analysis

## 📚 Documentation Index

### Production Setups
- [1M MPS Complete Documentation](realtime-platform-1million-events/README.md)
- [50K MPS Complete Documentation](realtime-platform-50k-events/README.md)

### Component Details
- [Flink Load Details (1M MPS)](realtime-platform-1million-events/FLINK-LOAD-DETAILS.md)
- [Pulsar Load Details (1M MPS)](realtime-platform-1million-events/PULSAR-LOAD-DETAILS.md)
- [ClickHouse Load Details (1M MPS)](realtime-platform-1million-events/CLICKHOUSE-LOAD-DETAILS.md)
- [Producer Load Details (1M MPS)](realtime-platform-1million-events/PRODUCER-LOAD-DETAILS.md)

### Deployment Guides
- [1M MPS Deployment Runbook](realtime-platform-1million-events/DEPLOYMENT-RUNBOOK.md)
- [50K MPS Deployment Runbook](realtime-platform-50k-events/DEPLOYMENT-RUNBOOK.md)

### Development
- [Local Setup Guide](local-setup/README.md)

## 🔧 Technology Stack

- **Orchestration**: Kubernetes (EKS/Kind)
- **Streaming**: Apache Pulsar
- **Processing**: Apache Flink
- **Storage**: ClickHouse
- **Monitoring**: Grafana + Prometheus
- **Infrastructure**: Terraform + AWS
- **Serialization**: AVRO
- **Containerization**: Docker

## 🤝 Contributing

This platform is designed for multi-domain event streaming. Each component is modular and can be adapted for specific use cases across different industries.

## 📄 License

This project is part of the RealtimeDataPlatform ecosystem for high-performance event streaming across multiple domains.
