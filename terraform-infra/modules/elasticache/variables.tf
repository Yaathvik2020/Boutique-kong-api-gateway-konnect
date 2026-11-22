variable "name" {
  description = "Name prefix, e.g. boutique-prod"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Database subnets (no internet route)"
  type        = list(string)
}

variable "allowed_security_group_id" {
  description = "EKS cluster security group (nodes and pods)"
  type        = string
}

variable "node_type" {
  type    = string
  default = "cache.t4g.micro"
}

variable "nodes" {
  description = "1 = single node. 2+ = primary + replica(s) in other AZs with automatic failover."
  type        = number
  default     = 1
}

variable "engine_version" {
  type    = string
  default = "7.1"
}

variable "parameter_group_name" {
  type    = string
  default = "default.redis7"
}

variable "snapshot_retention_days" {
  type    = number
  default = 0
}
