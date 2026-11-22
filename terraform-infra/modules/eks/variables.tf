variable "cluster_name" {
  type = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version. Upgrade one minor version at a time, dev first."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for the control plane ENIs and the worker nodes"
  type        = list(string)
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the Kubernetes API from the internet (office/VPN/CI). Empty = private API only."
  type        = list(string)
  default     = []
}

variable "admin_role_arns" {
  description = "IAM role ARNs that get cluster-admin (e.g. SSO admin role, CI deploy role)"
  type        = list(string)
  default     = []
}

variable "node_instance_types" {
  type = list(string)
}

variable "node_capacity_type" {
  description = "ON_DEMAND (prod) or SPOT (cheap dev)"
  type        = string
  default     = "ON_DEMAND"
}

variable "node_disk_size" {
  type    = number
  default = 50
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

variable "addon_versions" {
  description = "Pin EKS add-on versions, e.g. { vpc-cni = \"v1.x.y-eksbuild.1\" }. Missing = AWS default for the cluster version."
  type        = map(string)
  default     = {}
}

variable "log_retention_days" {
  type    = number
  default = 90
}
