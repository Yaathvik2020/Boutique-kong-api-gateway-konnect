# Cluster add-ons the platform needs, installed with Helm:
#   argo-cd                - GitOps: deploys the app + Kong data planes from Git
#   kube-prometheus-stack  - Prometheus, Alertmanager, Grafana
#   external-secrets       - copies AWS Secrets Manager -> Kubernetes Secrets (IRSA, read-only, this env only)
#   cluster-autoscaler     - adds/removes nodes (IRSA)
#   metrics-server         - CPU/memory metrics for HPA
#   aws-load-balancer-controller - creates the ALB (+WAF, ACM) from the Kong Ingress
#   external-dns           - creates the Route 53 record for the API hostname
#   gp3 StorageClass       - encrypted default volumes
# + IAM role for the Kong data planes: read the Redis password from Secrets Manager.
terraform {
  required_providers {
    aws        = { source = "hashicorp/aws" }
    helm       = { source = "hashicorp/helm" }
    kubernetes = { source = "hashicorp/kubernetes" }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  v = merge({
    argo_cd               = "10.18.2"
    aws_lb_controller     = "3.6.3"
    external_dns          = "1.24.0"
    kube_prometheus_stack = "93.6.1"
    external_secrets      = "2.15.0"
    cluster_autoscaler    = "9.60.0"
    metrics_server        = "3.14.0"
  }, var.chart_versions)
}

# ---------------- Storage ----------------
resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name        = "gp3"
    annotations = { "storageclass.kubernetes.io/is-default-class" = "true" }
  }
  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
  parameters = {
    type      = "gp3"
    encrypted = "true"
  }
}

# ---------------- IRSA helper ----------------
data "aws_iam_policy_document" "irsa_trust" {
  for_each = {
    external_secrets   = "external-secrets:external-secrets"
    cluster_autoscaler = "kube-system:cluster-autoscaler"
    aws_lb_controller  = "kube-system:aws-load-balancer-controller"
    external_dns       = "kube-system:external-dns"
    kong_dp            = "kong:kong-dp"
  }
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_issuer}:sub"
      values   = ["system:serviceaccount:${each.value}"]
    }
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# ---------------- External Secrets ----------------
resource "aws_iam_role" "external_secrets" {
  name               = "${var.cluster_name}-external-secrets"
  assume_role_policy = data.aws_iam_policy_document.irsa_trust["external_secrets"].json
}

resource "aws_iam_role_policy" "external_secrets" {
  name = "read-env-secrets"
  role = aws_iam_role.external_secrets.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = "arn:${data.aws_partition.current.partition}:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.secrets_prefix}/*"
    }]
  })
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  repository       = var.local_chart_dir == "" ? "https://charts.external-secrets.io" : null
  chart            = var.local_chart_dir == "" ? "external-secrets" : "${var.local_chart_dir}/external-secrets-${local.v.external_secrets}.tgz"
  version          = local.v.external_secrets

  values = [yamlencode({
    installCRDs = true
    serviceAccount = {
      name        = "external-secrets"
      annotations = { "eks.amazonaws.com/role-arn" = aws_iam_role.external_secrets.arn }
    }
  })]

  # The Load Balancer Controller adds a webhook that checks every new Service; install it
  # first (Helm waits for its pods), or other charts fail with "no endpoints available".
  depends_on = [helm_release.aws_lb_controller]
}

# ---------------- Cluster autoscaler ----------------
resource "aws_iam_role" "cluster_autoscaler" {
  name               = "${var.cluster_name}-cluster-autoscaler"
  assume_role_policy = data.aws_iam_policy_document.irsa_trust["cluster_autoscaler"].json
}

resource "aws_iam_role_policy" "cluster_autoscaler" {
  name = "scale-node-groups"
  role = aws_iam_role.cluster_autoscaler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups", "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations", "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeTags", "ec2:DescribeImages", "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplateVersions", "ec2:GetInstanceTypesFromInstanceRequirements",
          "eks:DescribeNodegroup",
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["autoscaling:SetDesiredCapacity", "autoscaling:TerminateInstanceInAutoScalingGroup"]
        Resource = "*"
        Condition = {
          StringEquals = { "aws:ResourceTag/k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned" }
        }
      },
    ]
  })
}

resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  namespace  = "kube-system"
  repository = var.local_chart_dir == "" ? "https://kubernetes.github.io/autoscaler" : null
  chart      = var.local_chart_dir == "" ? "cluster-autoscaler" : "${var.local_chart_dir}/cluster-autoscaler-${local.v.cluster_autoscaler}.tgz"
  version    = local.v.cluster_autoscaler

  values = [yamlencode(merge(
    {
      autoDiscovery = { clusterName = var.cluster_name }
      awsRegion     = var.region
      extraArgs     = { balance-similar-node-groups = true, skip-nodes-with-system-pods = false, expander = "least-waste" }
      rbac = {
        serviceAccount = {
          name        = "cluster-autoscaler"
          annotations = { "eks.amazonaws.com/role-arn" = aws_iam_role.cluster_autoscaler.arn }
        }
      }
    },
    var.cluster_autoscaler_image_tag == "" ? {} : { image = { tag = var.cluster_autoscaler_image_tag } }
  ))]

  # The Load Balancer Controller adds a webhook that checks every new Service; install it
  # first (Helm waits for its pods), or other charts fail with "no endpoints available".
  depends_on = [helm_release.aws_lb_controller]
}

# ---------------- Metrics server ----------------
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = var.local_chart_dir == "" ? "https://kubernetes-sigs.github.io/metrics-server/" : null
  chart      = var.local_chart_dir == "" ? "metrics-server" : "${var.local_chart_dir}/metrics-server-${local.v.metrics_server}.tgz"
  version    = local.v.metrics_server
  values     = [yamlencode({ replicas = var.ha ? 2 : 1 })]

  # The Load Balancer Controller adds a webhook that checks every new Service; install it
  # first (Helm waits for its pods), or other charts fail with "no endpoints available".
  depends_on = [helm_release.aws_lb_controller]
}

# ---------------- Monitoring ----------------
resource "helm_release" "monitoring" {
  name             = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true
  repository       = var.local_chart_dir == "" ? "https://prometheus-community.github.io/helm-charts" : null
  chart            = var.local_chart_dir == "" ? "kube-prometheus-stack" : "${var.local_chart_dir}/kube-prometheus-stack-${local.v.kube_prometheus_stack}.tgz"
  version          = local.v.kube_prometheus_stack
  timeout          = 900

  values = [yamlencode({
    prometheus = {
      prometheusSpec = {
        retention = var.prometheus_retention
        storageSpec = {
          volumeClaimTemplate = {
            spec = {
              storageClassName = kubernetes_storage_class_v1.gp3.metadata[0].name
              accessModes      = ["ReadWriteOnce"]
              resources        = { requests = { storage = var.prometheus_storage } }
            }
          }
        }
      }
    }
    alertmanager = {
      alertmanagerSpec = { replicas = var.ha ? 2 : 1 }
    }
    grafana = {
      # admin password: generated by the chart, secret monitoring/kube-prometheus-stack-grafana
      persistence = { enabled = true, storageClassName = kubernetes_storage_class_v1.gp3.metadata[0].name, size = "10Gi" }
    }
  })]

  # The Load Balancer Controller adds a webhook that checks every new Service; install it
  # first (Helm waits for its pods), or other charts fail with "no endpoints available".
  depends_on = [helm_release.aws_lb_controller]
}

# ---------------- Argo CD ----------------
resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = var.local_chart_dir == "" ? "https://argoproj.github.io/argo-helm" : null
  chart            = var.local_chart_dir == "" ? "argo-cd" : "${var.local_chart_dir}/argo-cd-${local.v.argo_cd}.tgz"
  version          = local.v.argo_cd
  timeout          = 900

  values = [yamlencode({
    configs = {
      params = { "server.insecure" = true } # reach it via kubectl port-forward; add an internal ingress + SSO later
    }
    server         = { replicas = var.ha ? 2 : 1, service = { type = "ClusterIP" } }
    repoServer     = { replicas = var.ha ? 2 : 1 }
    applicationSet = { replicas = var.ha ? 2 : 1 }
    "redis-ha"     = { enabled = var.ha }
    redis          = { enabled = !var.ha }
    controller     = { replicas = 1 }
  })]

  depends_on = [helm_release.monitoring, helm_release.aws_lb_controller] # CRDs first; LB controller webhook ready
}

# ---------------- AWS Load Balancer Controller ----------------
resource "aws_iam_role" "aws_lb_controller" {
  name               = "${var.cluster_name}-aws-lb-controller"
  assume_role_policy = data.aws_iam_policy_document.irsa_trust["aws_lb_controller"].json
}

resource "aws_iam_policy" "aws_lb_controller" {
  name   = "${var.cluster_name}-aws-lb-controller"
  policy = file("${path.module}/policies/aws-load-balancer-controller.json") # official policy from the controller repo
}

resource "aws_iam_role_policy_attachment" "aws_lb_controller" {
  role       = aws_iam_role.aws_lb_controller.name
  policy_arn = aws_iam_policy.aws_lb_controller.arn
}

resource "helm_release" "aws_lb_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = var.local_chart_dir == "" ? "https://aws.github.io/eks-charts" : null
  chart      = var.local_chart_dir == "" ? "aws-load-balancer-controller" : "${var.local_chart_dir}/aws-load-balancer-controller-${local.v.aws_lb_controller}.tgz"
  version    = local.v.aws_lb_controller

  values = [yamlencode({
    clusterName  = var.cluster_name
    region       = var.region
    vpcId        = var.vpc_id
    replicaCount = var.ha ? 2 : 1
    serviceAccount = {
      name        = "aws-load-balancer-controller"
      annotations = { "eks.amazonaws.com/role-arn" = aws_iam_role.aws_lb_controller.arn }
    }
  })]

  wait       = true # Terraform waits until the controller's pods (and its webhook) are ready
  depends_on = [aws_iam_role_policy_attachment.aws_lb_controller]
}

# ---------------- external-dns (Route 53 record for the API hostname) ----------------
resource "aws_iam_role" "external_dns" {
  name               = "${var.cluster_name}-external-dns"
  assume_role_policy = data.aws_iam_policy_document.irsa_trust["external_dns"].json
}

resource "aws_iam_role_policy" "external_dns" {
  name = "manage-api-records"
  role = aws_iam_role.external_dns.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["route53:ChangeResourceRecordSets"], Resource = [var.route53_zone_arn] },
      {
        Effect   = "Allow"
        Action   = ["route53:ListHostedZones", "route53:ListResourceRecordSets", "route53:ListTagsForResource"]
        Resource = "*"
      },
    ]
  })
}

resource "helm_release" "external_dns" {
  name       = "external-dns"
  namespace  = "kube-system"
  repository = var.local_chart_dir == "" ? "https://kubernetes-sigs.github.io/external-dns/" : null
  chart      = var.local_chart_dir == "" ? "external-dns" : "${var.local_chart_dir}/external-dns-${local.v.external_dns}.tgz"
  version    = local.v.external_dns

  values = [yamlencode({
    provider      = { name = "aws" }
    env           = [{ name = "AWS_DEFAULT_REGION", value = var.region }]
    domainFilters = [var.route53_zone_name]
    sources       = ["ingress"]
    policy        = "upsert-only"    # never deletes records it didn't create
    txtOwnerId    = var.cluster_name # dev/staging/prod clusters can share one zone safely
    registry      = "txt"
    serviceAccount = {
      name        = "external-dns"
      annotations = { "eks.amazonaws.com/role-arn" = aws_iam_role.external_dns.arn }
    }
  })]

  # The Load Balancer Controller adds a webhook that checks every new Service; install it
  # first (Helm waits for its pods), or other charts fail with "no endpoints available".
  depends_on = [helm_release.aws_lb_controller]
}

# ---------------- Kong data planes: read the Redis password from Secrets Manager ----------------
# Used by Kong's AWS vault: {vault://aws-sm/<secret-name>/password}. Only these secrets.
resource "aws_iam_role" "kong_dp" {
  name               = "${var.cluster_name}-kong-dp"
  assume_role_policy = data.aws_iam_policy_document.irsa_trust["kong_dp"].json
}

resource "aws_iam_role_policy" "kong_dp" {
  name = "read-kong-secrets"
  role = aws_iam_role.kong_dp.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = var.kong_secret_arns
    }]
  })
}
