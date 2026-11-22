output "issuer" {
  description = "OIDC issuer for Kong (DECK_OIDC_ISSUER)"
  value       = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.partners.id}"
}

output "token_url" {
  value = "https://${aws_cognito_user_pool_domain.partners.domain}.auth.${var.region}.amazoncognito.com/oauth2/token"
}

output "client_ids" {
  description = "partner -> Cognito app client ID (Kong consumer custom_id)"
  value       = { for p, c in aws_cognito_user_pool_client.partner : p => c.id }
}

output "secret_names" {
  value = { for p, s in aws_secretsmanager_secret.partner_oidc : p => s.name }
}
