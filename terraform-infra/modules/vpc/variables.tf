variable "name" {
  description = "Name prefix for every resource, e.g. boutique-prod"
  type        = string
}

variable "region" {
  description = "AWS region (used for the S3 endpoint name)"
  type        = string
}

variable "cidr_block" {
  description = "VPC CIDR, e.g. 10.20.0.0/16. Use a different range per environment."
  type        = string
}

variable "azs" {
  description = "Availability zones, e.g. [\"us-east-1a\", \"us-east-1b\", \"us-east-1c\"]"
  type        = list(string)
}

variable "cluster_name" {
  description = "EKS cluster name, for the subnet tags the load balancer controller needs"
  type        = string
}

variable "single_nat_gateway" {
  description = "true = one NAT for all AZs (cheap, dev). false = one NAT per AZ (HA, prod)."
  type        = bool
  default     = false
}

variable "enable_flow_logs" {
  type    = bool
  default = true
}

variable "flow_log_retention_days" {
  type    = number
  default = 30
}
