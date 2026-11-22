# Partner login with OAuth2 (machine-to-machine): Amazon Cognito issues access tokens,
# Kong's openid-connect plugin verifies them on /partner/v2/*.
#
#   partner --(client_id + client_secret)--> Cognito /oauth2/token --> access token (JWT, 1 h)
#   partner --(Authorization: Bearer <token>)--> Kong /partner/v2/products --> product-service
#
# One app client per partner. The client secret is stored in Secrets Manager so it can be
# handed to the partner (and used for tests); it is also in the Terraform state (encrypted S3).

data "aws_caller_identity" "current" {}

resource "aws_cognito_user_pool" "partners" {
  name                = "${var.name}-partners"
  deletion_protection = var.deletion_protection ? "ACTIVE" : "INACTIVE"
}

# Token endpoint: https://<domain>.auth.<region>.amazoncognito.com/oauth2/token
resource "aws_cognito_user_pool_domain" "partners" {
  domain       = "${var.name}-partners-${data.aws_caller_identity.current.account_id}"
  user_pool_id = aws_cognito_user_pool.partners.id
}

# The API and what partners may do with it: scope "boutique/partner.read"
resource "aws_cognito_resource_server" "boutique" {
  identifier   = "boutique"
  name         = "Boutique partner API"
  user_pool_id = aws_cognito_user_pool.partners.id

  scope {
    scope_name        = "partner.read"
    scope_description = "Read products through the partner API"
  }
}

resource "aws_cognito_user_pool_client" "partner" {
  for_each = toset(var.partners)

  name                                 = "partner-${each.key}"
  user_pool_id                         = aws_cognito_user_pool.partners.id
  generate_secret                      = true
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["client_credentials"]
  allowed_oauth_scopes                 = ["${aws_cognito_resource_server.boutique.identifier}/partner.read"]
  supported_identity_providers         = ["COGNITO"]
  access_token_validity                = 60
  token_validity_units { access_token = "minutes" }
}

resource "aws_secretsmanager_secret" "partner_oidc" {
  for_each                = toset(var.partners)
  name                    = "${var.secrets_prefix}/partner-${each.key}-oidc"
  description             = "OAuth2 client credentials for partner ${each.key} (Cognito)"
  recovery_window_in_days = var.recovery_window_days
}

resource "aws_secretsmanager_secret_version" "partner_oidc" {
  for_each  = toset(var.partners)
  secret_id = aws_secretsmanager_secret.partner_oidc[each.key].id
  secret_string = jsonencode({
    client_id     = aws_cognito_user_pool_client.partner[each.key].id
    client_secret = aws_cognito_user_pool_client.partner[each.key].client_secret
    token_url     = "https://${aws_cognito_user_pool_domain.partners.domain}.auth.${var.region}.amazoncognito.com/oauth2/token"
    scope         = "boutique/partner.read"
  })
}
