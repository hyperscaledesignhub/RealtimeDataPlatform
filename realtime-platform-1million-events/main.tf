# ================================================================================
# MERGED LOW-COST INFRASTRUCTURE FOR FLINK, PULSAR, AND CLICKHOUSE
# ================================================================================
#
# This Terraform configuration creates a SINGLE shared EKS cluster that hosts:
#   1. Apache Flink (stream processing)
#   2. Apache Pulsar (message broker)
#   3. ClickHouse (analytics database)
#
# Cluster Name: benchmark-low-infra
# VPC CIDR: 10.1.0.0/16
# Single AZ: us-west-2a (first available) - ALL WORKLOADS IN SAME AZ TO AVOID DATA TRANSFER COSTS
#
# Total Node Groups: 7
#   - Flink: 2 node groups (TaskManager, JobManager)
#   - Pulsar: 3 node groups (ZooKeeper, Broker, BookKeeper)
#   - ClickHouse: 1 node group
#   - General: 1 node group (shared services)
#
# Estimated Cost: ~$300-400/month (with spot instances: ~$150-200/month)
#
# Deploy this ONCE to create cluster for all three services!
# ================================================================================

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }

  # backend "s3" {
  #   # Configure this after creating the S3 bucket in us-west-2
  #   bucket = "flink-benchmark-terraform-state-us-west-2"
  #   key    = "04-10-2025/terraform.tfstate"
  #   region = "us-west-2"
  #   # dynamodb_table = "flink-benchmark-terraform-locks"
  #   encrypt = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "flink-benchmark"
      Environment = var.environment
      InfraType   = "high-cost"
      ManagedBy   = "terraform"
    }
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      module.eks.cluster_name,
      "--region",
      var.aws_region
    ]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks",
        "get-token",
        "--cluster-name",
        module.eks.cluster_name,
        "--region",
        var.aws_region
      ]
    }
  }
}

# VPC Module
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = [data.aws_availability_zones.available.names[0], data.aws_availability_zones.available.names[1]]  # Two AZs (EKS requirement)
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  enable_nat_gateway   = true
  single_nat_gateway   = true  # Single NAT for cost savings (already set)
  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  tags = {
    Name = "${var.cluster_name}-vpc"
  }
}

# Local variables to handle conditional node groups
locals {
  # Base node group configurations
  pulsar_zookeeper_config = {
    name = "pulsar-zk"
    instance_types = ["t3.medium"]
    capacity_type  = var.use_spot_instances ? "SPOT" : "ON_DEMAND"
    min_size     = 1
    max_size     = 5
    desired_size = var.pulsar_zookeeper_desired_size
    disk_size = 30
    disk_type = "gp3"
    subnet_ids = [module.vpc.private_subnets[0]]
    labels = {
      component    = "zookeeper"
      "pulsar-role" = "zookeeper"
      "node-type"   = "zookeeper"
      workload     = "pulsar"
      service      = "pulsar"
    }
    taints = []
    tags = {
      Name      = "${var.cluster_name}-pulsar-zookeeper"
      Service   = "pulsar"
      Component = "zookeeper"
    }
    enable_monitoring = false
    iam_role_additional_policies = {
      AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
    }
  }

  pulsar_broker_bookie_config = {
    name = "pulsar-broker-bookie"
    instance_types = ["i7i.8xlarge"]
    capacity_type  = var.use_spot_instances ? "SPOT" : "ON_DEMAND"
    min_size     = 4
    max_size     = 8
    desired_size = var.pulsar_broker_desired_size
    disk_size = 100
    disk_type = "gp3"
    subnet_ids = [module.vpc.private_subnets[0]]
    labels = {
      component    = "broker-bookie"
      "pulsar-role" = "broker-bookie"
      "node-type"   = "broker-bookie"
      "node.kubernetes.io/instance-type" = "i3en.6xlarge"
      "storage-type" = "nvme"
      workload     = "pulsar"
      service      = "pulsar"
      # Additional labels for compatibility
      "bookie-component" = "bookie"
      "broker-component" = "broker"
    }
    taints = [
      {
        key    = "pulsar-broker"
        value  = "true"
        effect = "NO_SCHEDULE"
      },
      {
        key    = "pulsar-bookkeeper"
        value  = "true"
        effect = "NO_SCHEDULE"
      }
    ]
    pre_bootstrap_user_data = <<-EOT
      #!/bin/bash
      # Format and mount NVMe drives for Broker-Bookie combination
      
      # Wait for NVMe drives to be available
      while [ ! -e /dev/nvme1n1 ] || [ ! -e /dev/nvme2n1 ]; do
        sleep 5
      done
      
      # Create filesystems on NVMe drives
      mkfs.ext4 -F /dev/nvme1n1
      mkfs.ext4 -F /dev/nvme2n1
      
      # Create mount points
      mkdir -p /mnt/bookkeeper-ledgers
      mkdir -p /mnt/bookkeeper-journal
      # Mount the drives
      mount /dev/nvme1n1 /mnt/bookkeeper-ledgers
      mount /dev/nvme2n1 /mnt/bookkeeper-journal
      # Add to fstab for persistence
      echo "/dev/nvme1n1 /mnt/bookkeeper-ledgers ext4 defaults,noatime 0 2" >> /etc/fstab
      echo "/dev/nvme2n1 /mnt/bookkeeper-journal ext4 defaults,noatime 0 2" >> /etc/fstab
      # Set permissions
      chmod 755 /mnt/bookkeeper-ledgers /mnt/bookkeeper-journal
      chown -R 1000:1000 /mnt/bookkeeper-ledgers /mnt/bookkeeper-journal
    EOT
    tags = {
      Name      = "${var.cluster_name}-pulsar-broker-bookie"
      Service   = "pulsar"
      Component = "pulsar-broker-bookie"
    }
    enable_monitoring = true
    iam_role_additional_policies = {
      AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
    }
  }

  pulsar_proxy_config = {
    name = "pulsar-proxy"
    instance_types = ["c5.2xlarge"]
    capacity_type  = var.use_spot_instances ? "SPOT" : "ON_DEMAND"
    min_size     = 1
    max_size     = 3
    desired_size = var.pulsar_proxy_desired_size
    disk_size = 30
    disk_type = "gp3"
    subnet_ids = [module.vpc.private_subnets[0]]
    labels = {
      component     = "proxy"
      "pulsar-role" = "proxy"
      "node-type"   = "proxy"
      workload      = "pulsar"
      service       = "pulsar"
    }
    taints = []
    tags = {
      Name      = "${var.cluster_name}-pulsar-proxy"
      Service   = "pulsar"
      Component = "proxy"
    }
    enable_monitoring = true
    iam_role_additional_policies = {
      AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
    }
  }

  producer_nodes_config = {
    name = "producer"
    instance_types = ["c5.4xlarge"]
    capacity_type  = var.use_spot_instances ? "SPOT" : "ON_DEMAND"
    min_size     = 2
    max_size     = 16
    desired_size = var.producer_desired_size
    disk_size = 100
    disk_type = "gp3"
    subnet_ids = [module.vpc.private_subnets[0]]
    labels = {
      workload = "producer"
      service  = "producer"
      component = "producer"
      "workload-type" = "performance-testing"
    }
    tags = {
      Name      = "${var.cluster_name}-producer"
      Service   = "producer"
      Component = "producer"
      Purpose   = "performance-testing"
    }
    enable_monitoring = true
    iam_role_additional_policies = {
      AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
    }
  }

  clickhouse_nodes_config = {
    name = "clickhouse"
    instance_types = ["r6id.4xlarge"]
    capacity_type  = var.use_spot_instances ? "SPOT" : "ON_DEMAND"
    min_size     = 6
    max_size     = 12
    desired_size = var.clickhouse_desired_size
    ami_type       = "AL2023_x86_64_STANDARD"
    disk_size      = 100
    subnet_ids = [module.vpc.private_subnets[0]]
    labels = {
      workload = "clickhouse"
      "node.kubernetes.io/instance-type" = "r6id.4xlarge"
      node_group     = "clickhouse_nodes"
      service        = "clickhouse"
    }
    taints = [
      {
        key    = "clickhouse"
        value  = "true"
        effect = "NO_SCHEDULE"
      }
    ]
    pre_bootstrap_user_data = <<-EOT
      #!/bin/bash
      # Setup NVMe instance store
      if lsblk | grep -q nvme1n1; then
        echo "Setting up NVMe instance store..."
        mkfs.xfs /dev/nvme1n1
        mkdir -p /mnt/nvme-clickhouse
        mount /dev/nvme1n1 /mnt/nvme-clickhouse
        echo "/dev/nvme1n1 /mnt/nvme-clickhouse xfs defaults,nofail 0 2" >> /etc/fstab
        chmod 755 /mnt/nvme-clickhouse
      fi
      
      # Create directories for ClickHouse
      mkdir -p /mnt/nvme-clickhouse/clickhouse/hot
      mkdir -p /mnt/ebs-clickhouse/clickhouse/warm
      
      # Set ownership (ClickHouse runs as UID 101)
      chown -R 101:101 /mnt/nvme-clickhouse/clickhouse/ || true
      chown -R 101:101 /mnt/ebs-clickhouse/clickhouse/ || true
    EOT
    enable_monitoring = true
    tags = {
      Name    = "${var.cluster_name}-clickhouse"
      Service = "clickhouse"
    }
    iam_role_additional_policies = {
      AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
    }
  }

  clickhouse_query_nodes_config = {
    name = "clickhouse-query"
    instance_types = ["c5.2xlarge"]
    capacity_type  = var.use_spot_instances ? "SPOT" : "ON_DEMAND"
    min_size     = 1
    max_size     = 6
    desired_size = var.clickhouse_query_desired_size
    ami_type       = "AL2023_x86_64_STANDARD"
    disk_size      = 50
    subnet_ids = [module.vpc.private_subnets[0]]
    labels = {
      workload = "clickhouse-query"
      "node.kubernetes.io/instance-type" = "c5.2xlarge"
      node_group     = "clickhouse_query_nodes"
      service        = "clickhouse-query"
    }
    taints = [
      {
        key    = "clickhouse-query"
        value  = "true"
        effect = "NO_SCHEDULE"
      }
    ]
    enable_monitoring = true
    tags = {
      Name    = "${var.cluster_name}-clickhouse-query"
      Service = "clickhouse-query"
    }
    iam_role_additional_policies = {
      AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
    }
  }

  general_nodes_config = {
    name = "general"
    instance_types = ["t3.medium"]
    capacity_type  = var.use_spot_instances ? "SPOT" : "ON_DEMAND"
    min_size     = 2
    max_size     = 4
    desired_size = 2
    disk_size = 20
    disk_type = "gp3"
    subnet_ids = [module.vpc.private_subnets[0]]
    labels = {
      component     = "general"
      "node-type"   = "general"
      workload      = "system"
      service       = "general"
    }
    taints = []  # No taints - allows system pods to schedule
    tags = {
      Name      = "${var.cluster_name}-general"
      Service   = "system"
      Component = "general"
    }
    enable_monitoring = true
    iam_role_additional_policies = {
      AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
    }
  }

  # Conditional node groups - using for_each approach to avoid type issues
  pulsar_node_groups = {
    for k, v in {
      pulsar_zookeeper = var.enable_pulsar ? local.pulsar_zookeeper_config : null
      pulsar_broker_bookie = var.enable_pulsar ? local.pulsar_broker_bookie_config : null
      pulsar_proxy = var.enable_pulsar ? local.pulsar_proxy_config : null
    } : k => v if v != null
  }

  producer_node_groups = {
    for k, v in {
      producer_nodes = var.enable_producer ? local.producer_nodes_config : null
    } : k => v if v != null
  }

  clickhouse_node_groups = {
    for k, v in {
      clickhouse_nodes       = var.enable_clickhouse ? local.clickhouse_nodes_config : null
      clickhouse_query_nodes = var.enable_clickhouse ? local.clickhouse_query_nodes_config : null
    } : k => v if v != null
  }
}

locals {
  flink_taskmanager_config = {
    name           = "flink-tm"
    instance_types = ["c5.4xlarge"] # 16 vCPU, 32 GiB RAM (upgraded for high performance)
    capacity_type  = var.use_spot_instances ? "SPOT" : "ON_DEMAND"
    min_size       = 1
    max_size       = 6
    desired_size   = var.flink_taskmanager_desired_size
    disk_size      = 50
    disk_type      = "gp3"
    subnet_ids     = [module.vpc.private_subnets[0]]
    labels = {
      role     = "flink-taskmanager"
      workload = "flink"
      service  = "flink"
    }
    taints = []
    tags = {
      Name    = "${var.cluster_name}-flink-taskmanager"
      Service = "flink"
    }
    enable_monitoring            = false
    iam_role_additional_policies = {
      AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
    }
  }

  flink_jobmanager_config = {
    name           = "flink-jm"
          instance_types = ["c5.4xlarge"]  # 16 vCPU, 32 GiB RAM (upgraded for high performance)
    capacity_type  = var.use_spot_instances ? "SPOT" : "ON_DEMAND"
    min_size       = 1
    max_size       = 2
    desired_size   = var.flink_jobmanager_desired_size
    disk_size      = 30
    disk_type      = "gp3"
    subnet_ids     = [module.vpc.private_subnets[0]]
    labels = {
      role     = "flink-jobmanager"
      workload = "flink"
      service  = "flink"
    }
    taints = []
    tags = {
      Name    = "${var.cluster_name}-flink-jobmanager"
      Service = "flink"
    }
    enable_monitoring            = false
    iam_role_additional_policies = {
      AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
    }
  }

  flink_node_groups = {
    for k, v in {
      flink_taskmanager = var.enable_flink ? local.flink_taskmanager_config : null
      flink_jobmanager  = var.enable_flink ? local.flink_jobmanager_config : null
    } : k => v if v != null
  }
}

# EKS Module - Low Cost Configuration
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Cluster endpoint access
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # Enable IRSA (IAM Roles for Service Accounts)
  enable_irsa = true

  # Cluster addons
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
      service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
    }
  }

  # Minimal logging for cost savings
  cluster_enabled_log_types = ["api", "audit"]

  # EKS Managed Node Groups - Conditional Configuration Based on Variables
  # This cluster can host: Flink, Pulsar, and/or ClickHouse workloads
  eks_managed_node_groups = merge(
    
    # ========================================================================
    # FLINK NODE GROUPS (from locals)
    # ========================================================================
    local.flink_node_groups,
    
    # ========================================================================
    # PULSAR NODE GROUPS (from locals)
    # ========================================================================
    local.pulsar_node_groups,
    
    # ========================================================================
    # CLICKHOUSE NODE GROUPS (from locals)
    # ========================================================================
    local.clickhouse_node_groups,
    
    # ========================================================================
    # PRODUCER NODE GROUPS (from locals)
    # ========================================================================
    local.producer_node_groups,
    
    # ========================================================================
    # GENERAL PURPOSE NODE GROUP (Conditional)
    # ========================================================================
    var.enable_general_nodes ? {
      # General workload nodes - For supporting services and utilities
      general_nodes = {
      name = "general"

      instance_types = ["t3.medium"]  # 2 vCPU, 4 GiB RAM (cost-effective for system pods)
      capacity_type  = var.use_spot_instances ? "SPOT" : "ON_DEMAND"

      min_size     = 1
      max_size     = 4
      desired_size = var.general_desired_size

      disk_size = 30
      disk_type = "gp3"

      # Force instances to single AZ for cost savings
      subnet_ids = [module.vpc.private_subnets[0]]

      labels = {
        workload = "general"
        service  = "shared"
      }

      taints = []

      tags = {
        Name    = "${var.cluster_name}-general"
        Service = "shared"
      }

      enable_monitoring = false

      iam_role_additional_policies = {
        AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
      }
    }
    } : {},
    
  )

  # aws-auth configmap
  manage_aws_auth_configmap = true

  tags = {
    Name = var.cluster_name
  }
}

# EBS CSI Driver IRSA
module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "ebs-csi-driver"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = {
    Name = "${var.cluster_name}-ebs-csi-driver"
  }
}

# ECR Repository for Flink Job Image (Optional)
resource "aws_ecr_repository" "flink_job" {
  count = var.create_ecr_repository ? 1 : 0
  
  name                 = "${var.cluster_name}-flink-job"
  image_tag_mutability = "MUTABLE"
  force_delete         = true  # Allow deletion even if repository contains images

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = "${var.cluster_name}-flink-job"
  }
}

# ECR Lifecycle Policy (Optional)
resource "aws_ecr_lifecycle_policy" "flink_job" {
  count = var.create_ecr_repository ? 1 : 0
  
  repository = aws_ecr_repository.flink_job[0].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 5 images"
        selection = {
          tagStatus     = "any"
          countType     = "imageCountMoreThan"
          countNumber   = 5
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# S3 Bucket for Flink Checkpoints and Savepoints
resource "aws_s3_bucket" "flink_state" {
  bucket = "${var.cluster_name}-flink-state-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${var.cluster_name}-flink-state"
  }
}

resource "aws_s3_bucket_versioning" "flink_state" {
  bucket = aws_s3_bucket.flink_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "flink_state" {
  bucket = aws_s3_bucket.flink_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "flink_state" {
  bucket = aws_s3_bucket.flink_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Lifecycle policy for cost savings
resource "aws_s3_bucket_lifecycle_configuration" "flink_state" {
  bucket = aws_s3_bucket.flink_state.id

  rule {
    id     = "delete-old-checkpoints"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = 7  # Delete checkpoints after 7 days
    }

    noncurrent_version_expiration {
      noncurrent_days = 3
    }
  }
}

# IAM Role for Flink to access S3
resource "aws_iam_role" "flink_s3_access" {
  name = "flink-s3-access"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:flink-benchmark:flink"
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.cluster_name}-flink-s3-access"
  }
}

resource "aws_iam_role_policy" "flink_s3_access" {
  name = "flink-s3-policy"
  role = aws_iam_role.flink_s3_access.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:ListBucket"
        ],
        Resource = [
          "arn:aws:s3:::s3-platform-flink"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ],
        Resource = [
          "arn:aws:s3:::s3-platform-flink/*"
        ]
      }
    ]
  })
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

