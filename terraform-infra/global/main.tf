# Account-wide resources shared by all environments.
# ECR: images are built ONCE and the same image (same tag) moves dev -> staging -> prod.
locals {
  services = ["frontend", "auth", "orders", "order-service", "product-service", "user-service"]
}

resource "aws_ecr_repository" "this" {
  for_each = toset(local.services)

  name                 = "boutique/${each.value}"
  image_tag_mutability = "IMMUTABLE" # a tag always means the same image

  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "KMS" }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last 50 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 50 }
      action       = { type = "expire" }
    }]
  })
}
