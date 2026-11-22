terraform {
  required_version = ">= 1.11" # S3 native state locking (use_lockfile) is GA from 1.11
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.73" }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = { Project = "boutique", ManagedBy = "terraform", Stack = "global" }
  }
}
