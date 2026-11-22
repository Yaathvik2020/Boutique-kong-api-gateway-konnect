variable "name" {
  description = "Identifier, e.g. boutique-prod"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "database_subnet_ids" {
  type = list(string)
}

variable "allowed_security_group_id" {
  description = "Security group allowed to connect (EKS cluster security group)"
  type        = string
}

variable "engine_major_version" {
  type    = string
  default = "18"
}

variable "instance_class" {
  type = string
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "max_allocated_storage" {
  description = "Storage autoscaling upper limit (GiB)"
  type        = number
  default     = 100
}

variable "master_username" {
  type    = string
  default = "boutique_admin"
}

variable "multi_az" {
  description = "Standby in a second AZ with automatic failover (prod)"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  type    = number
  default = 7
}

variable "deletion_protection" {
  type    = bool
  default = true
}
