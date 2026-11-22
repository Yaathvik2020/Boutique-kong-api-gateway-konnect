variable "cluster_name" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "route53_zone_name" {
  description = "Public hosted zone external-dns may write to"
  type        = string
}

variable "route53_zone_arn" {
  type = string
}

variable "kong_secret_arns" {
  description = "Secrets Manager ARNs the Kong data planes may read (Redis password)"
  type        = list(string)
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_issuer" {
  description = "OIDC issuer host without https:// (eks module output)"
  type        = string
}

variable "secrets_prefix" {
  description = "External Secrets may read only Secrets Manager secrets under this prefix, e.g. boutique/prod"
  type        = string
}

variable "ha" {
  description = "Run add-ons with 2 replicas (staging/prod)"
  type        = bool
  default     = false
}

variable "prometheus_retention" {
  type    = string
  default = "7d"
}

variable "prometheus_storage" {
  type    = string
  default = "20Gi"
}

variable "chart_versions" {
  description = "Override pinned Helm chart versions: argo_cd, kube_prometheus_stack, external_secrets, cluster_autoscaler, metrics_server, aws_lb_controller, external_dns"
  type        = map(string)
  default     = {}
}

variable "cluster_autoscaler_image_tag" {
  description = "cluster-autoscaler image tag matching the Kubernetes minor version, e.g. v1.37.0. Empty = chart default (chart 9.60.0 ships v1.37.0)."
  type        = string
  default     = ""
}

variable "local_chart_dir" {
  description = "Install the add-on charts from local .tgz files in this folder (scripts/download-charts.sh) instead of downloading them during plan/apply. Empty = download from the chart repositories."
  type        = string
  default     = ""
}
