# One environment = one VPC + one EKS cluster + its add-ons + (optionally) RDS + its secrets.
# This file is identical in envs/dev, envs/staging and envs/prod.
# Only terraform.tfvars (sizes, HA on/off) and backend.tf (state location) differ.

locals {
  name           = "boutique-${var.environment}" # VPC, cluster, RDS names
  secrets_prefix = "boutique/${var.environment}" # Secrets Manager prefix
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source = "../../modules/vpc"

  name                    = local.name
  region                  = var.region
  cidr_block              = var.vpc_cidr
  azs                     = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  cluster_name            = local.name
  single_nat_gateway      = var.single_nat_gateway
  flow_log_retention_days = var.log_retention_days
}

module "eks" {
  source = "../../modules/eks"

  cluster_name        = local.name
  kubernetes_version  = var.kubernetes_version
  private_subnet_ids  = module.vpc.private_subnet_ids
  public_access_cidrs = var.cluster_public_access_cidrs
  admin_role_arns     = var.cluster_admin_role_arns

  node_instance_types = var.node_instance_types
  node_capacity_type  = var.node_capacity_type
  node_min_size       = var.node_min_size
  node_desired_size   = var.node_desired_size
  node_max_size       = var.node_max_size
  addon_versions      = var.eks_addon_versions
  log_retention_days  = var.log_retention_days
}

# RDS only where enable_rds = true (staging/prod). Dev uses the in-cluster Postgres.
module "rds" {
  source = "../../modules/rds"
  count  = var.enable_rds ? 1 : 0

  name                      = local.name
  vpc_id                    = module.vpc.vpc_id
  database_subnet_ids       = module.vpc.database_subnet_ids
  allowed_security_group_id = module.eks.cluster_security_group_id
  instance_class            = var.rds_instance_class
  multi_az                  = var.rds_multi_az
  backup_retention_days     = var.rds_backup_retention_days
  deletion_protection       = var.deletion_protection
}

# Redis for Kong's rate-limiting-advanced (one shared counter for all Kong pods)
module "redis" {
  source = "../../modules/elasticache"

  name                      = local.name
  vpc_id                    = module.vpc.vpc_id
  subnet_ids                = module.vpc.database_subnet_ids
  allowed_security_group_id = module.eks.cluster_security_group_id
  node_type                 = var.redis_node_type
  nodes                     = var.redis_nodes
}

# Edge: ACM certificate + AWS WAF + ALB access logs for https://<api_hostname>
module "edge" {
  source = "../../modules/edge"

  name                    = local.name
  route53_zone_name       = var.route53_zone_name
  api_hostname            = var.api_hostname
  waf_rate_limit_per_5min = var.waf_rate_limit_per_5min
  allowed_country_codes   = var.waf_allowed_country_codes
  log_retention_days      = var.log_retention_days
  deletion_protection     = var.deletion_protection
}

module "app_secrets" {
  source = "../../modules/app-secrets"

  prefix               = local.secrets_prefix
  db_host              = var.enable_rds ? module.rds[0].address : "boutique-postgres"
  db_username          = var.enable_rds ? module.rds[0].username : "postgres"
  db_password          = var.enable_rds ? module.rds[0].password : ""
  db_ssl               = var.enable_rds
  redis_secret_name    = "${local.name}-kong-redis"
  redis_host           = module.redis.host
  redis_password       = module.redis.password
  recovery_window_days = var.deletion_protection ? 7 : 0
}

module "addons" {
  source          = "../../modules/addons"
  local_chart_dir = var.local_chart_dir

  cluster_name                 = module.eks.cluster_name
  region                       = var.region
  vpc_id                       = module.vpc.vpc_id
  route53_zone_name            = var.route53_zone_name
  route53_zone_arn             = module.edge.route53_zone_arn
  kong_secret_arns             = [module.app_secrets.redis_secret_arn]
  oidc_provider_arn            = module.eks.oidc_provider_arn
  oidc_issuer                  = module.eks.oidc_issuer
  secrets_prefix               = local.secrets_prefix
  ha                           = var.addons_ha
  prometheus_retention         = var.prometheus_retention
  prometheus_storage           = var.prometheus_storage
  cluster_autoscaler_image_tag = var.cluster_autoscaler_image_tag

  depends_on = [module.eks] # nodes + EBS driver must exist before Helm installs
}

# Partner login (OAuth2 client credentials): Cognito issues tokens, Kong verifies them
module "partner_auth" {
  source               = "../../modules/partner-auth"
  name                 = local.name
  region               = var.region
  secrets_prefix       = local.secrets_prefix
  deletion_protection  = var.deletion_protection
  recovery_window_days = var.deletion_protection ? 7 : 0
}
