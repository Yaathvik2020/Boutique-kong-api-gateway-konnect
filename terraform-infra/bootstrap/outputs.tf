output "state_bucket" {
  description = "Put this in envs/*/backend.tf and global/backend.tf"
  value       = aws_s3_bucket.state.bucket
}

output "github_ci_role_arn" {
  description = "GitHub secret AWS_CI_ROLE_ARN (image builds)"
  value       = aws_iam_role.ci.arn
}

output "github_terraform_role_arn" {
  description = "GitHub secret AWS_TERRAFORM_ROLE_ARN; also add to cluster_admin_role_arns"
  value       = aws_iam_role.terraform.arn
}

output "github_deck_role_arn" {
  description = "GitHub secret AWS_DECK_ROLE_ARN (decK sync: reads the Konnect token + partner keys)"
  value       = aws_iam_role.deck.arn
}
