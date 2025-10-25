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
      InfraType   = "low-cost"
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
    # FLINK NODE GROUPS (Conditional)
    # ========================================================================
    var.enable_flink ? {
      # Flink TaskManager nodes - Process streaming data
      flink_taskmanager = {
      name = "flink-tm"

      instance_types = ["t3.medium"]  # 2 vCPU, 4 GiB RAM
      capacity_type  = var.use_spot_instances ? "SPOT" : "ON_DEMAND"

      min_size     = 1
      max_size     = 6
      desired_size = var.flink_taskmanager_desired_size

      disk_size = 50
      disk_type = "gp3"

      # Force instances to single AZ for cost savings
      subnet_ids = [module.vpc.private_subnets[0]]

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

      enable_monitoring = false

      iam_role_additional_policies = {
        AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
      }
    }

    # Flink JobManager nodes - Coordinate Flink jobs
    flink_jobmanager = {
      name = "flink-jm"

      instance_types = ["t3.small"]  # 2 vCPU, 2 GiB RAM
      capacity_type  = var.use_spot_instances ? "SPOT" : "ON_DEMAND"

      min_size     = 1
      max_size     = 2
      desired_size = var.flink_jobmanager_desired_size

      disk_size = 30
      disk_type = "gp3"

      # Force instances to single AZ for cost savings
      subnet_ids = [module.vpc.private_subnets[0]]

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

      enable_monitoring = false

      iam_role_additional_policies = {
        AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
      }
    }
    } : {},
    
    # ========================================================================
    # PULSAR NODE GROUPS (Conditional)
    # ========================================================================
    var.enable_pulsar ? {
      # Pulsar ZooKeeper nodes - Coordination service for Pulsar
      pulsar_zookeeper = {
      name = "pulsar-zk"

      instance_types = ["t3.small"]  # 2 vCPU, 2 GiB RAM
      capacity_type  = var.use_spot_instances ? "SPOT" : "ON_DEMAND"

      min_size     = 1
      max_size     = 5
      desired_size = var.pulsar_zookeeper_desired_size

      disk_size = 30
      disk_type = "gp3"

      # Force instances to single AZ for cost savings
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

    # Pulsar Broker nodes - Handle pub/sub messaging
    pulsar_broker = {
      name = "pulsar-broker"

      instance_types = ["t3.medium"]  # 2 vCPU, 4 GiB RAM
      capacity_type  = var.use_spot_instances ? "SPOT" : "ON_DEMAND"

      min_size     = 1
      max_size     = 4
      desired_size = var.pulsar_broker_desired_size

      disk_size = 50
      disk_type = "gp3"

      # Force instances to single AZ for cost savings
      subnet_ids = [module.vpc.private_subnets[0]]

      labels = {
        component    = "broker"
        "pulsar-role" = "broker"
        "node-type"   = "broker"
        workload     = "pulsar"
        service      = "pulsar"
      }

      taints = []

      tags = {
        Name      = "${var.cluster_name}-pulsar-broker"
        Service   = "pulsar"
        Component = "broker"
      }

      enable_monitoring = false

      iam_role_additional_policies = {
        AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
      }
    }

    # Pulsar BookKeeper nodes - Store message data
    pulsar_bookkeeper = {
      name = "pulsar-bk"

      instance_types = ["t3.medium"]  # 2 vCPU, 4 GiB RAM (not i3 for cost)
      capacity_type  = var.use_spot_instances ? "SPOT" : "ON_DEMAND"

      min_size     = 3
      max_size     = 5
      desired_size = var.pulsar_bookkeeper_desired_size

      disk_size = 100  # Larger disk for message storage
      disk_type = "gp3"

      # Force instances to single AZ for cost savings
      subnet_ids = [module.vpc.private_subnets[0]]

      labels = {
        component    = "bookie"
        "pulsar-role" = "bookie"
        "node-type"   = "bookkeeper"
        workload     = "pulsar"
        service      = "pulsar"
      }

      taints = []

      tags = {
        Name      = "${var.cluster_name}-pulsar-bookkeeper"
        Service   = "pulsar"
        Component = "bookkeeper"
      }

      enable_monitoring = false

      iam_role_additional_policies = {
        AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
      }
    },

    # Pulsar Proxy nodes - Client connections and load balancing
    pulsar_proxy = {
      name = "pulsar-proxy"

      instance_types = ["t3.small"]  # 2 vCPU, 2 GiB RAM
      capacity_type  = var.use_spot_instances ? "SPOT" : "ON_DEMAND"

      min_size     = 1
      max_size     = 3
      desired_size = var.pulsar_proxy_desired_size

      disk_size = 30
      disk_type = "gp3"

      # Force instances to single AZ for cost savings
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

      enable_monitoring = false

      iam_role_additional_policies = {
        AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
      }
    }
    } : {},
    
    # ========================================================================
    # CLICKHOUSE NODE GROUPS (Conditional)
    # ========================================================================
    var.enable_clickhouse ? {
      # ClickHouse database nodes - Analytics database
      clickhouse_nodes = {
      name = "clickhouse"

      instance_types = ["t3.xlarge"]  # 4 vCPU, 16 GiB RAM
      capacity_type  = var.use_spot_instances ? "SPOT" : "ON_DEMAND"

      min_size     = 1
      max_size     = 5
      desired_size = var.clickhouse_desired_size

      disk_size = 50
      disk_type = "gp3"

      # Force instances to single AZ for cost savings
      subnet_ids = [module.vpc.private_subnets[0]]

      labels = {
        workload       = "clickhouse"
        node_group     = "clickhouse_nodes"  # For ClickHouse operator compatibility
        service        = "clickhouse"
      }

      taints = [
        {
          key    = "clickhouse"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      ]

      tags = {
        Name    = "${var.cluster_name}-clickhouse"
        Service = "clickhouse"
      }

      enable_monitoring = false

      iam_role_additional_policies = {
        AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
      }
    }
    } : {},
    
    # ========================================================================
    # GENERAL PURPOSE NODE GROUP (Conditional)
    # ========================================================================
    var.enable_general_nodes ? {
      # General workload nodes - For supporting services and utilities
      general_nodes = {
      name = "general"

      instance_types = ["t3.small"]  # 2 vCPU, 2 GiB RAM
      capacity_type  = var.use_spot_instances ? "SPOT" : "ON_DEMAND"

      min_size     = 1
      max_size     = 4
      desired_size = 4

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
    
    # ========================================================================
    # IOT PRODUCER NODE GROUP (Conditional)
    # ========================================================================
    var.enable_producer ? {
      # IoT Data Producer nodes - Generates sensor data to Pulsar
      producer_nodes = {
      name = "producer"

      instance_types = ["t3.medium"]  # 2 vCPU, 4 GiB RAM
      capacity_type  = var.use_spot_instances ? "SPOT" : "ON_DEMAND"

      min_size     = 1
      max_size     = 5
      desired_size = var.producer_desired_size

      disk_size = 20
      disk_type = "gp3"

      # Force instances to single AZ for cost savings (avoid cross-AZ data transfer)
      subnet_ids = [module.vpc.private_subnets[0]]

      labels = {
        workload = "bench-producer"
        service  = "producer"
      }

      taints = []

      tags = {
        Name      = "${var.cluster_name}-producer"
        Service   = "producer"
        Component = "data-generator"
      }

      enable_monitoring = false

      iam_role_additional_policies = {
        AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
      }
    }
    } : {}
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

# ECR Repository for Flink Job Image
resource "aws_ecr_repository" "flink_job" {
  name                 = "${var.cluster_name}-flink-job"
  image_tag_mutability = "MUTABLE"

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

# ECR Lifecycle Policy
resource "aws_ecr_lifecycle_policy" "flink_job" {
  repository = aws_ecr_repository.flink_job.name

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
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.flink_state.arn,
          "${aws_s3_bucket.flink_state.arn}/*"
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

