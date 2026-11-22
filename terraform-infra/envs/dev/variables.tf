variable "environment" {
  description = "dev, staging or prod"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod."
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

# ---------------- Network ----------------
variable "vpc_cidr" {
  description = "Different per environment so VPCs can be peered later"
  type        = string
}

variable "az_count" {
  type    = number
  default = 3
}

variable "single_nat_gateway" {
  description = "true = one NAT (cheap). false = one NAT per AZ (HA)."
  type        = bool
}

# ---------------- Edge (Route 53 -> ALB + WAF -> Kong) ----------------
variable "route53_zone_name" {
  description = "Existing public hosted zone, e.g. ksysglobaltech.online"
  type        = string
}

variable "api_hostname" {
  description = "Public API hostname for this env, e.g. api-dev.ksysglobaltech.online"
  type        = string
}

variable "waf_rate_limit_per_5min" {
  type    = number
  default = 2000
}

variable "waf_allowed_country_codes" {
  description = "Empty = all countries. e.g. [\"IN\"] to allow India only."
  type        = list(string)
  default     = []
}

# ---------------- EKS ----------------
variable "kubernetes_version" {
  type = string
}

variable "cluster_public_access_cidrs" {
  description = "Who may reach the Kubernetes API from the internet (office/VPN/CI IPs). Empty = private only."
  type        = list(string)
  default     = []
}

variable "cluster_admin_role_arns" {
  description = "IAM roles that get cluster-admin (SSO admin role, CI deploy role)"
  type        = list(string)
  default     = []
}

variable "node_instance_types" {
  type = list(string)
}

variable "node_capacity_type" {
  type    = string
  default = "ON_DEMAND"
}

variable "node_min_size" {
  type = number
}

variable "node_desired_size" {
  type = number
}

variable "node_max_size" {
  type = number
}

variable "eks_addon_versions" {
  type    = map(string)
  default = {}
}

variable "cluster_autoscaler_image_tag" {
  type    = string
  default = ""
}

# ---------------- Database ----------------
variable "enable_rds" {
  description = "true = Amazon RDS (staging/prod). false = in-cluster Postgres (dev)."
  type        = bool
}

variable "rds_instance_class" {
  type    = string
  default = "db.t4g.medium"
}

variable "rds_multi_az" {
  type    = bool
  default = false
}

variable "rds_backup_retention_days" {
  type    = number
  default = 7
}

# ---------------- Redis (Kong rate limiting) ----------------
variable "redis_node_type" {
  type    = string
  default = "cache.t4g.micro"
}

variable "redis_nodes" {
  description = "1 = single node. 2 = primary + replica in another AZ, automatic failover."
  type        = number
  default     = 1
}

# ---------------- Add-ons / ops ----------------
variable "addons_ha" {
  description = "2 replicas for Argo CD, Alertmanager, metrics-server"
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

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "deletion_protection" {
  description = "Protect RDS and secrets from accidental deletion (staging/prod)"
  type        = bool
  default     = true
}

variable "local_chart_dir" {
  description = "Folder with the add-on chart .tgz files (scripts/download-charts.sh), e.g. /home/<you>/charts. Empty = download charts during plan/apply."
  type        = string
  default     = ""
}
