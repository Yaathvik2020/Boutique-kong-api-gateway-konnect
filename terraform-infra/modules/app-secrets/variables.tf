variable "prefix" {
  description = "Secrets Manager name prefix, e.g. boutique/prod"
  type        = string
}

variable "db_host" {
  description = "RDS address, or boutique-postgres for the in-cluster Postgres (dev)"
  type        = string
}

variable "db_username" {
  type = string
}

variable "db_password" {
  description = "RDS master password. Empty = generate one (in-cluster Postgres)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "db_ssl" {
  description = "true for RDS (SSL forced), false for the in-cluster Postgres"
  type        = bool
}

variable "redis_secret_name" {
  description = "Secrets Manager name for the Redis secret, without slashes, e.g. boutique-prod-kong-redis"
  type        = string
}

variable "redis_host" {
  description = "ElastiCache primary endpoint"
  type        = string
}

variable "redis_password" {
  description = "ElastiCache AUTH token"
  type        = string
  sensitive   = true
}

variable "recovery_window_days" {
  description = "Days a deleted secret can still be restored (0 = delete immediately, dev only)"
  type        = number
  default     = 7
}
