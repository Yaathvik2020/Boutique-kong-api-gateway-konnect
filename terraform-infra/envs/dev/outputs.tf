output "cluster_name" {
  value = module.eks.cluster_name
}

output "configure_kubectl" {
  value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region} --alias ${var.environment}"
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "nat_public_ips" {
  description = "Outbound IPs of this cluster (for partner allow-lists)"
  value       = module.vpc.nat_public_ips
}

output "rds_address" {
  value = var.enable_rds ? module.rds[0].address : "in-cluster Postgres (boutique-postgres)"
}

output "app_secret_name" {
  value = module.app_secrets.app_secret_name
}

output "konnect_cert_secret_name" {
  description = "Put the Konnect data plane certificate here (k8s-kong/scripts/put-konnect-cert.sh)"
  value       = module.app_secrets.konnect_cert_secret_name
}

output "external_secrets_role_arn" {
  value = module.addons.external_secrets_role_arn
}

output "redis_host" {
  description = "kong-config/envs/<env>.env -> DECK_REDIS_HOST"
  value       = module.redis.host
}

output "redis_secret_name" {
  description = "kong-config/envs/<env>.env -> DECK_REDIS_SECRET"
  value       = module.app_secrets.redis_secret_name
}

# ---- copy these into k8s-kong/kong-dp/values-<env>.yaml ----
output "api_url" {
  value = "https://${var.api_hostname}"
}

output "acm_certificate_arn" {
  value = module.edge.certificate_arn
}

output "waf_acl_arn" {
  value = module.edge.waf_acl_arn
}

output "alb_logs_bucket" {
  value = module.edge.alb_logs_bucket
}

output "kong_dp_role_arn" {
  value = module.addons.kong_dp_role_arn
}

output "vpc_cidr" {
  description = "Kong trusted_ips (the ALB's X-Forwarded-For is trusted from inside the VPC)"
  value       = module.vpc.vpc_cidr
}

output "oidc_issuer" {
  description = "kong-config/envs/<env>.env DECK_OIDC_ISSUER"
  value       = module.partner_auth.issuer
}

output "partner_acme_client_id" {
  description = "kong-config/envs/<env>.env DECK_PARTNER_ACME_CLIENT_ID"
  value       = module.partner_auth.client_ids["acme"]
}

output "partner_token_url" {
  value = module.partner_auth.token_url
}
