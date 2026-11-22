variable "name" {
  description = "Name prefix, e.g. boutique-prod"
  type        = string
}

variable "route53_zone_name" {
  description = "Existing PUBLIC hosted zone in this account, e.g. ksysglobaltech.online"
  type        = string
}

variable "api_hostname" {
  description = "Public API hostname in that zone, e.g. api.ksysglobaltech.online"
  type        = string
}

variable "waf_rate_limit_per_5min" {
  description = "WAF blocks a client IP above this many requests per 5 minutes (all paths)"
  type        = number
  default     = 2000
}

variable "allowed_country_codes" {
  description = "If set, WAF blocks other countries, e.g. [\"IN\"]. Empty = all countries."
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "deletion_protection" {
  type    = bool
  default = true
}
