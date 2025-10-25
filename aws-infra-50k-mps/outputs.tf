output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster OIDC Issuer"
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC Provider for EKS"
  value       = module.eks.oidc_provider_arn
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnets
}

output "ecr_repository_url" {
  description = "URL of the ECR repository for Flink job"
  value       = aws_ecr_repository.flink_job.repository_url
}

output "ecr_repository_arn" {
  description = "ARN of the ECR repository"
  value       = aws_ecr_repository.flink_job.arn
}

output "s3_bucket_name" {
  description = "Name of S3 bucket for Flink state"
  value       = aws_s3_bucket.flink_state.id
}

output "s3_bucket_arn" {
  description = "ARN of S3 bucket for Flink state"
  value       = aws_s3_bucket.flink_state.arn
}

output "flink_s3_access_role_arn" {
  description = "IAM role ARN for Flink S3 access"
  value       = aws_iam_role.flink_s3_access.arn
}

output "ebs_csi_driver_role_arn" {
  description = "IAM role ARN for EBS CSI driver"
  value       = module.ebs_csi_irsa.iam_role_arn
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "taskmanager_node_group_id" {
  description = "TaskManager node group ID"
  value       = var.enable_flink ? module.eks.eks_managed_node_groups["flink_taskmanager"].node_group_id : null
}

output "jobmanager_node_group_id" {
  description = "JobManager node group ID"
  value       = var.enable_flink ? module.eks.eks_managed_node_groups["flink_jobmanager"].node_group_id : null
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "estimated_monthly_cost" {
  description = "Estimated monthly cost (USD)"
  value       = "~$150-200/month (2x t3.medium + 1x t3.small + NAT Gateway + EKS control plane)"
}

