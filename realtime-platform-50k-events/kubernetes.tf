# Kubernetes resources for low-cost infrastructure

# Storage Class for GP3 (basic configuration)
resource "kubernetes_storage_class" "gp3_flink" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner = "ebs.csi.aws.com"
  reclaim_policy      = "Delete"  # Delete volumes to save costs
  volume_binding_mode = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    iops      = "3000"      # Lower IOPS for cost savings
    throughput = "125"      # Lower throughput
    fsType    = "ext4"
    encrypted = "true"
  }

  depends_on = [
    module.eks
  ]
}

# Flink Benchmark Namespace
resource "kubernetes_namespace" "flink_benchmark" {
  metadata {
    name = var.flink_namespace

    labels = {
      name        = var.flink_namespace
      environment = var.environment
      infra-type  = "low-cost"
      managed-by  = "terraform"
    }
  }

  depends_on = [
    module.eks
  ]
}

# Flink Service Account
resource "kubernetes_service_account" "flink" {
  metadata {
    name      = "flink"
    namespace = kubernetes_namespace.flink_benchmark.metadata[0].name

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.flink_s3_access.arn
    }
  }

  depends_on = [
    module.eks
  ]
}

# Flink RBAC - Role
resource "kubernetes_role" "flink" {
  metadata {
    name      = "flink"
    namespace = kubernetes_namespace.flink_benchmark.metadata[0].name
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "configmaps"]
    verbs      = ["*"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "deployments/finalizers"]
    verbs      = ["*"]
  }

  rule {
    api_groups = ["extensions"]
    resources  = ["deployments"]
    verbs      = ["*"]
  }

  depends_on = [
    module.eks
  ]
}

# Flink RBAC - RoleBinding
resource "kubernetes_role_binding" "flink" {
  metadata {
    name      = "flink"
    namespace = kubernetes_namespace.flink_benchmark.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.flink.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.flink.metadata[0].name
    namespace = kubernetes_namespace.flink_benchmark.metadata[0].name
  }

  depends_on = [
    module.eks
  ]
}

# Metrics Server
resource "helm_release" "metrics_server" {
  count = var.enable_metrics_server ? 1 : 0

  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = "3.11.0"

  set {
    name  = "args[0]"
    value = "--kubelet-insecure-tls"
  }

  depends_on = [
    module.eks
  ]
}

# Flink Operator Namespace
resource "kubernetes_namespace" "flink_operator" {
  count = var.install_flink_operator ? 1 : 0

  metadata {
    name = "flink-operator"

    labels = {
      name       = "flink-operator"
      managed-by = "terraform"
    }
  }

  depends_on = [
    module.eks
  ]
}

# Install cert-manager (required for Flink operator webhooks)
resource "helm_release" "cert_manager" {
  count = var.install_flink_operator ? 1 : 0

  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = "cert-manager"
  create_namespace = true
  version    = "v1.15.0"

  set {
    name  = "crds.enabled"
    value = "true"
  }

  depends_on = [
    module.eks
  ]
}

# Install Flink Kubernetes Operator using Helm
resource "helm_release" "flink_operator" {
  count = var.install_flink_operator ? 1 : 0

  name       = "flink-kubernetes-operator"
  repository = "https://downloads.apache.org/flink/flink-kubernetes-operator-1.13.0/"
  chart      = "flink-kubernetes-operator"
  namespace  = kubernetes_namespace.flink_operator[0].metadata[0].name
  version    = "1.13.0"

  set {
    name  = "image.repository"
    value = "apache/flink-kubernetes-operator"
  }

  set {
    name  = "image.tag"
    value = "1.13.0"
  }

  set {
    name  = "watchNamespaces[0]"
    value = ""
  }

  set {
    name  = "webhook.create"
    value = "false"
  }

  set {
    name  = "metrics.port"
    value = "9999"
  }

  # Reduce resource requests for low-cost setup
  set {
    name  = "resources.requests.memory"
    value = "512Mi"
  }

  set {
    name  = "resources.requests.cpu"
    value = "250m"
  }

  set {
    name  = "resources.limits.memory"
    value = "1Gi"
  }

  set {
    name  = "resources.limits.cpu"
    value = "500m"
  }

  depends_on = [
    module.eks,
    kubernetes_namespace.flink_operator,
    helm_release.cert_manager
  ]
}

