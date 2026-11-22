variable "name" {
  description = "Name prefix, e.g. boutique-dev"
  type        = string
}

variable "region" {
  type = string
}

variable "secrets_prefix" {
  description = "Secrets Manager prefix, e.g. boutique/dev"
  type        = string
}

variable "partners" {
  description = "One OAuth2 app client per partner"
  type        = list(string)
  default     = ["acme"]
}

variable "deletion_protection" {
  type    = bool
  default = false
}

variable "recovery_window_days" {
  type    = number
  default = 0
}
