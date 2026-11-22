# DEV — small and cheap. Breakage here is fine; this is where changes land first.
environment = "dev"
region      = "us-east-1"

# Network
vpc_cidr           = "10.10.0.0/16"
az_count           = 2    # 2 AZs are enough for dev
single_nat_gateway = true # one NAT (~$32/month) instead of one per AZ

# Edge: Route 53 -> ALB (AWS WAF, ACM TLS) -> Kong data planes -> services
route53_zone_name         = "ksysglobaltech.online" # existing PUBLIC hosted zone in this AWS account
api_hostname              = "ksys-dev.ksysglobaltech.online"
waf_rate_limit_per_5min   = 2000
waf_allowed_country_codes = []

# EKS
kubernetes_version          = "1.37"
cluster_public_access_cidrs = ["0.0.0.0/0"] # TODO: your office/VPN IP, e.g. ["49.36.12.34/32"]
cluster_admin_role_arns     = [arn:aws:iam::214920156606:user/Sudhan-ksys]            # e.g. ["arn:aws:iam::214920156606:role/boutique-github-deploy"]

node_instance_types = ["t3.large", "t3a.large", "m5.large"] # several types = fewer Spot interruptions
node_capacity_type  = "SPOT"                                # ~70% cheaper; nodes can be reclaimed (fine for dev)
node_min_size       = 1
node_desired_size   = 2
node_max_size       = 3

# Database: in-cluster Postgres (k8s-kong/overlays/dev)
enable_rds = false

# Redis for Kong rate limiting: 1 small node (~$12/month)
redis_node_type = "cache.t4g.micro"
redis_nodes     = 1

# Add-ons / ops
addons_ha            = false
prometheus_retention = "3d"
prometheus_storage   = "10Gi"
log_retention_days   = 7
deletion_protection  = false # dev can be destroyed and rebuilt
