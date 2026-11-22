# Global state (bucket from terraform-infra/bootstrap). S3 native locking, no DynamoDB.
# Replace 214920156606 with your AWS account ID.
terraform {
  backend "s3" {
    bucket       = "boutique-tfstate-214920156606"
    key          = "global/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
