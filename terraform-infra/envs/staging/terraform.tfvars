# STAGING — a smaller copy of prod. Same features as prod (RDS, HA add-ons,
# 3 AZs) so upgrades and releases are tested on a prod-like setup first.
environment = "staging"
region      = "us-east-1"

# Network
vpc_cidr           = "10.20.0.0/16"
az_count           = 3
single_nat_gateway = true # saves 2 NATs; the only HA shortcut vs prod

# Edge: Route 53 -> ALB (AWS WAF, ACM TLS) -> Kong data planes -> services
route53_zone_name         = "ksysglobaltech.online" # existing PUBLIC hosted zone in this AWS account
api_hostname              = "api-staging.ksysglobaltech.online"
waf_rate_limit_per_5min   = 2000
waf_allowed_country_codes = []

# EKS
kubernetes_version          = "1.37"
cluster_public_access_cidrs = ["0.0.0.0/0"] # learning setup: GitHub-hosted runners have changing IPs. Real staging: office/VPN IPs + a self-hosted runner
cluster_admin_role_arns     = []            # e.g. ["arn:aws:iam::214920156606:role/boutique-github-deploy"]

node_instance_types = ["m6i.large"]
node_capacity_type  = "ON_DEMAND"
node_min_size       = 2
node_desired_size   = 3
node_max_size       = 5

# Database: Amazon RDS, single AZ
enable_rds                = true
rds_instance_class        = "db.t4g.medium"
rds_multi_az              = false
rds_backup_retention_days = 3

# Redis for Kong rate limiting: 1 node
redis_node_type = "cache.t4g.small"
redis_nodes     = 1

# Add-ons / ops
addons_ha            = true
prometheus_retention = "7d"
prometheus_storage   = "20Gi"
log_retention_days   = 30
deletion_protection  = false # learning setup (easy teardown). Real staging: true
