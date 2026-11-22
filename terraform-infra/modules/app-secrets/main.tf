# App secrets in AWS Secrets Manager. External Secrets (in the cluster) copies
# them into the Kubernetes Secret "boutique-secrets" the services already use.
#
#   <prefix>/app                   - DB URLs, DB password, JWT secrets (generated here)
#   <redis_secret_name>            - Redis endpoint + password, read DIRECTLY by Kong (AWS vault, IRSA).
#                                    No slashes in the name: Kong vault references are
#                                    {vault://aws-sm/<secret-name>/<json-key>}
#   <prefix>/konnect-cluster-cert  - Kong data plane certificate from Konnect
#                                    (JSON keys: crt, key). Empty here; fill it with
#                                    k8s-kong/scripts/put-konnect-cert.sh
terraform {
  required_providers {
    aws    = { source = "hashicorp/aws" }
    random = { source = "hashicorp/random" }
  }
}

resource "random_password" "db" {
  count   = var.db_password == "" ? 1 : 0 # dev: in-cluster Postgres gets a generated password
  length  = 32
  special = false
}

resource "random_id" "jwt" {
  byte_length = 32
}

resource "random_id" "jwt_refresh" {
  byte_length = 32
}

locals {
  db_password = var.db_password != "" ? var.db_password : random_password.db[0].result
  # node-postgres: sslmode=no-verify = encrypted connection (RDS forces SSL), certificate not checked.
  # To also verify the certificate, mount the RDS CA bundle and use sslmode=verify-full.
  url_suffix = var.db_ssl ? "?sslmode=no-verify" : ""
  base_url   = "postgresql://${var.db_username}:${local.db_password}@${var.db_host}:5432"
}

resource "aws_secretsmanager_secret" "app" {
  name                    = "${var.prefix}/app"
  description             = "Boutique app secrets (${var.prefix}). Synced to Kubernetes by External Secrets."
  recovery_window_in_days = var.recovery_window_days
}

resource "aws_secretsmanager_secret_version" "app" {
  secret_id = aws_secretsmanager_secret.app.id
  secret_string = jsonencode({
    POSTGRES_PASSWORD  = local.db_password
    DB_HOST            = var.db_host
    DB_USER            = var.db_username
    PGSSLMODE          = var.db_ssl ? "require" : "disable"
    AUTH_DB_URL        = "${local.base_url}/auth_db${local.url_suffix}"
    PRODUCTS_DB_URL    = "${local.base_url}/products_db${local.url_suffix}"
    ORDERS_DB_URL      = "${local.base_url}/orders_db${local.url_suffix}"
    USERS_DB_URL       = "${local.base_url}/users_db${local.url_suffix}"
    JWT_SECRET         = random_id.jwt.hex
    JWT_REFRESH_SECRET = random_id.jwt_refresh.hex
  })
}

resource "aws_secretsmanager_secret" "konnect_cert" {
  name                    = "${var.prefix}/konnect-cluster-cert"
  description             = "Kong data plane certificate for the Konnect control plane of this env. JSON keys: crt, key"
  recovery_window_in_days = var.recovery_window_days
}

resource "aws_secretsmanager_secret" "redis" {
  name                    = var.redis_secret_name
  description             = "ElastiCache Redis for Kong rate limiting. Read by the Kong data planes via {vault://aws-sm/${var.redis_secret_name}/password}."
  recovery_window_in_days = var.recovery_window_days
}

resource "aws_secretsmanager_secret_version" "redis" {
  secret_id = aws_secretsmanager_secret.redis.id
  secret_string = jsonencode({
    host     = var.redis_host
    port     = 6379
    password = var.redis_password
  })
}
