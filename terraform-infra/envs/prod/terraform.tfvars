# PROD — big and highly available. Changes arrive here only after dev and staging.
environment = "prod"
region      = "us-east-1"

# Network
vpc_cidr           = "10.30.0.0/16"
az_count           = 3
single_nat_gateway = false # one NAT per AZ: losing one AZ doesn't cut outbound traffic

# Edge: Route 53 -> ALB (AWS WAF, ACM TLS) -> Kong data planes -> services
route53_zone_name         = "ksysglobaltech.online" # existing PUBLIC hosted zone in this AWS account
api_hostname              = "api.ksysglobaltech.online"
waf_rate_limit_per_5min   = 2000
waf_allowed_country_codes = [] # e.g. ["IN"] if only India should reach the API

# EKS
kubernetes_version          = "1.37"
cluster_public_access_cidrs = [] # private API only: run terraform/kubectl from inside the VPC (VPN, bastion, self-hosted runner)
cluster_admin_role_arns     = [] # e.g. ["arn:aws:iam::214920156606:role/boutique-github-deploy", "<SSO admin role ARN>"]

node_instance_types = ["m6i.xlarge"]
node_capacity_type  = "ON_DEMAND"
node_min_size       = 3 # one per AZ
node_desired_size   = 3
node_max_size       = 9

# Database: Amazon RDS, Multi-AZ with automatic failover
enable_rds                = true
rds_instance_class        = "db.r6g.large"
rds_multi_az              = true
rds_backup_retention_days = 14

# Redis for Kong rate limiting: primary + replica in another AZ, automatic failover
redis_node_type = "cache.t4g.medium" # ~$100/month for 2 nodes; move to cache.m7g.large if Redis CPU stays high
redis_nodes     = 2

# Add-ons / ops
addons_ha            = true
prometheus_retention = "15d"
prometheus_storage   = "50Gi"
log_retention_days   = 90
deletion_protection  = true
