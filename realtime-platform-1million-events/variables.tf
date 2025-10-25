variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "development"
}

variable "cluster_name" {
  description = "Name of the EKS cluster (shared across all low-cost infra)"
  type        = string
  default     = "bench-low-infra"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.31"
}

# VPC Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR blocks (minimum 2 AZs required by EKS)"
  type        = list(string)
  default     = ["10.1.0.0/20", "10.1.16.0/20"]  # 4096 IPs each - enough for all workloads in single AZ
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks (minimum 2 AZs required by EKS)"
  type        = list(string)
  default     = ["10.1.101.0/24", "10.1.102.0/24"]  # Two subnets in two AZs (smaller, just for NAT/ELB)
}

# Cost Optimization
variable "use_spot_instances" {
  description = "Use spot instances for additional cost savings (recommended for dev/test)"
  type        = bool
  default     = true
}

# ================================================================================
# OPTIONAL SERVICE INSTALLATION - Choose which services to deploy
# ================================================================================

variable "enable_flink" {
  description = "Enable Flink node groups and infrastructure"
  type        = bool
  default     = true
}

variable "enable_pulsar" {
  description = "Enable Pulsar node groups and infrastructure"
  type        = bool
  default     = true
}

variable "enable_clickhouse" {
  description = "Enable ClickHouse node groups and infrastructure"
  type        = bool
  default     = true
}

variable "enable_general_nodes" {
  description = "Enable general purpose node groups (required for operators)"
  type        = bool
  default     = true
}

# ================================================================================
# FLINK CONFIGURATION
# ================================================================================

variable "flink_namespace" {
  description = "Kubernetes namespace for Flink"
  type        = string
  default     = "flink-benchmark"
}

variable "install_flink_operator" {
  description = "Install Flink Kubernetes Operator"
  type        = bool
  default     = true
}

variable "flink_operator_version" {
  description = "Flink Kubernetes Operator version"
  type        = string
  default     = "1.7.0"
}

# Flink Node Group Configuration
variable "flink_taskmanager_desired_size" {
  description = "Desired number of Flink TaskManager nodes"
  type        = number
  default     = 2
}

variable "flink_jobmanager_desired_size" {
  description = "Desired number of Flink JobManager nodes"
  type        = number
  default     = 1
}

# ================================================================================
# PULSAR CONFIGURATION
# ================================================================================

variable "pulsar_namespace" {
  description = "Kubernetes namespace for Pulsar"
  type        = string
  default     = "pulsar"
}

# Pulsar Node Group Configuration
variable "pulsar_zookeeper_desired_size" {
  description = "Desired number of Pulsar ZooKeeper nodes"
  type        = number
  default     = 3
}

variable "pulsar_broker_desired_size" {
  description = "Desired number of Pulsar Broker nodes"
  type        = number
  default     = 3
}

variable "pulsar_bookkeeper_desired_size" {
  description = "Desired number of Pulsar BookKeeper nodes"
  type        = number
  default     = 3
}

variable "pulsar_proxy_desired_size" {
  description = "Desired number of Pulsar Proxy nodes"
  type        = number
  default     = 2
}

# ================================================================================
# CLICKHOUSE CONFIGURATION
# ================================================================================

variable "clickhouse_namespace" {
  description = "Kubernetes namespace for ClickHouse"
  type        = string
  default     = "clickhouse"
}

# ClickHouse Node Group Configuration
variable "clickhouse_desired_size" {
  description = "Desired number of ClickHouse database nodes"
  type        = number
  default     = 3
}

variable "clickhouse_query_desired_size" {
  description = "Desired number of ClickHouse query nodes"
  type        = number
  default     = 2
}

variable "general_desired_size" {
  description = "Desired number of general purpose nodes"
  type        = number
  default     = 2
}

# ================================================================================
# IOT PRODUCER CONFIGURATION
# ================================================================================

variable "enable_producer" {
  description = "Enable IoT Producer node groups and infrastructure"
  type        = bool
  default     = true
}

# ================================================================================
# ECR CONFIGURATION
# ================================================================================

variable "create_ecr_repository" {
  description = "Create ECR repository for Flink job images"
  type        = bool
  default     = false  # Set to false to make ECR independent
}

# Producer Node Group Configuration
variable "producer_desired_size" {
  description = "Desired number of IoT Producer nodes"
  type        = number
  default     = 3
}

# Monitoring Configuration
variable "enable_metrics_server" {
  description = "Install Kubernetes metrics server"
  type        = bool
  default     = true
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}

