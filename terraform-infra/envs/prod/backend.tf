# Where prod's Terraform state is stored (bucket from terraform-infra/bootstrap).
# Locking: S3 native lock file (use_lockfile, Terraform >= 1.11). No DynamoDB table.
# Backend blocks can't use variables: replace 214920156606 with your AWS account ID.
terraform {
  backend "s3" {
    bucket       = "boutique-tfstate-214920156606"
    key          = "envs/prod/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true # writes envs/prod/terraform.tfstate.tflock next to the state while a run holds the lock
  }
}
