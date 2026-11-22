variable "region" {
  type    = string
  default = "us-east-1"
}

variable "github_repo" {
  description = "owner/name of the GitHub repo whose workflows may assume the roles"
  type        = string
}
