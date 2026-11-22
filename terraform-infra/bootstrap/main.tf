# Run ONCE per AWS account, with local state (no backend block on purpose).
# Creates what every other stack needs:
#   - S3 bucket for Terraform remote state; locking uses S3 native lock files
#     (use_lockfile = true in every backend.tf), so no DynamoDB table
#   - GitHub Actions OIDC provider + deploy role (pipelines get short-lived
#     credentials; no AWS access keys stored in GitHub)
terraform {
  required_version = ">= 1.11" # S3 native state locking (use_lockfile) is GA from 1.11
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.73" }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = { Project = "boutique", ManagedBy = "terraform", Stack = "bootstrap" }
  }
}

data "aws_caller_identity" "current" {}

# ---------------- Remote state ----------------
resource "aws_s3_bucket" "state" {
  bucket = "boutique-tfstate-${data.aws_caller_identity.current.account_id}"
  lifecycle { prevent_destroy = true }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration { status = "Enabled" } # every state change can be rolled back
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "aws:kms" }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------- GitHub Actions OIDC ----------------
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_policy_document" "github_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      # GitHub sends either repo:<owner>/<repo>:... or repo:<owner>@<id>/<repo>@<id>:...
      values = [
        "repo:${var.github_repo}:*",
        "repo:${split("/", var.github_repo)[0]}@*/${split("/", var.github_repo)[1]}@*:*",
      ]
    }
  }
}

# CI role: push images to ECR. Infrastructure changes run with a separate, broader role.
resource "aws_iam_role" "ci" {
  name               = "boutique-github-ci"
  assume_role_policy = data.aws_iam_policy_document.github_trust.json
}

resource "aws_iam_role_policy" "ci_ecr" {
  name = "push-images"
  role = aws_iam_role.ci.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:CompleteLayerUpload",
          "ecr:DescribeImages", "ecr:GetDownloadUrlForLayer", "ecr:InitiateLayerUpload",
          "ecr:PutImage", "ecr:UploadLayerPart",
        ]
        Resource = "arn:aws:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/boutique/*"
      },
    ]
  })
}

# Terraform role for the infrastructure pipeline. Starts broad; tighten once stable.
resource "aws_iam_role" "terraform" {
  name               = "boutique-github-terraform"
  assume_role_policy = data.aws_iam_policy_document.github_trust.json
}

resource "aws_iam_role_policy_attachment" "terraform" {
  role       = aws_iam_role.terraform.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# decK pipeline role: reads ONLY the Konnect token and the partner API keys from
# Secrets Manager (kong-config/deck.sh), so no Konnect token is stored in GitHub.
resource "aws_iam_role" "deck" {
  name               = "boutique-github-deck"
  assume_role_policy = data.aws_iam_policy_document.github_trust.json
}

resource "aws_iam_role_policy" "deck_secrets" {
  name = "read-deck-secrets"
  role = aws_iam_role.deck.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = [
        "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:boutique/konnect-deck-token-*",
        "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:boutique/*/partner-api-keys-*",
      ]
    }]
  })
}
