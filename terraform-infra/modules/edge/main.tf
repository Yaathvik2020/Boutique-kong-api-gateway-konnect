# Edge for one environment:  client -> Route 53 -> ALB (+ AWS WAF, ACM TLS) -> Kong data planes
#
# Created here:  ACM certificate (DNS-validated in Route 53), WAF web ACL, ALB access-log bucket.
# Created in the cluster: the ALB itself (AWS Load Balancer Controller, from the Kong chart's
# Ingress) and the Route 53 record (external-dns). Both use the outputs of this module.
terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

data "aws_caller_identity" "current" {}
data "aws_elb_service_account" "this" {}

data "aws_route53_zone" "this" {
  name         = var.route53_zone_name
  private_zone = false
}

# ---------------- TLS certificate ----------------
resource "aws_acm_certificate" "api" {
  domain_name       = var.api_hostname
  validation_method = "DNS"
  lifecycle { create_before_destroy = true }
}

resource "aws_route53_record" "validation" {
  for_each = {
    for o in aws_acm_certificate.api.domain_validation_options : o.domain_name => {
      name   = o.resource_record_name
      type   = o.resource_record_type
      record = o.resource_record_value
    }
  }
  zone_id         = data.aws_route53_zone.this.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "api" {
  certificate_arn         = aws_acm_certificate.api.arn
  validation_record_fqdns = [for r in aws_route53_record.validation : r.fqdn]
}

# ---------------- AWS WAF ----------------
locals {
  managed_rules = [
    { name = "AWSManagedRulesAmazonIpReputationList", priority = 10 }, # known bad IPs, bots
    { name = "AWSManagedRulesCommonRuleSet", priority = 20 },          # OWASP-style common attacks
    { name = "AWSManagedRulesKnownBadInputsRuleSet", priority = 30 },  # Log4j, bad payloads
    { name = "AWSManagedRulesSQLiRuleSet", priority = 40 },            # SQL injection
  ]
}

resource "aws_wafv2_web_acl" "this" {
  name  = "${var.name}-api"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  dynamic "rule" {
    for_each = length(var.allowed_country_codes) > 0 ? [1] : []
    content {
      name     = "geo-allow-list"
      priority = 5
      action {
        block {}
      }
      statement {
        not_statement {
          statement {
            geo_match_statement { country_codes = var.allowed_country_codes }
          }
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "geo-allow-list"
        sampled_requests_enabled   = true
      }
    }
  }

  dynamic "rule" {
    for_each = local.managed_rules
    content {
      name     = rule.value.name
      priority = rule.value.priority
      override_action {
        none {} # use count {} while tuning a rule group that blocks good traffic
      }
      statement {
        managed_rule_group_statement {
          vendor_name = "AWS"
          name        = rule.value.name
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = rule.value.name
        sampled_requests_enabled   = true
      }
    }
  }

  # Flood protection before traffic reaches Kong (Kong's 300/min per API is the finer limit)
  rule {
    name     = "rate-limit-per-ip"
    priority = 50
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit_per_5min
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit-per-ip"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name}-api"
    sampled_requests_enabled   = true
  }
}

resource "aws_cloudwatch_log_group" "waf" {
  name              = "aws-waf-logs-${var.name}" # WAF requires the aws-waf-logs- prefix
  retention_in_days = var.log_retention_days
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  resource_arn            = aws_wafv2_web_acl.this.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]
  redacted_fields {
    single_header { name = "authorization" }
  }
}

# ---------------- ALB access logs ----------------
resource "aws_s3_bucket" "alb_logs" {
  bucket        = "${var.name}-alb-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = !var.deletion_protection
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket                  = aws_s3_bucket.alb_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" } # ALB log delivery needs SSE-S3
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule {
    id     = "expire"
    status = "Enabled"
    filter {}
    expiration { days = var.log_retention_days }
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "ALBAccessLogs"
      Effect    = "Allow"
      Principal = { AWS = data.aws_elb_service_account.this.arn }
      Action    = "s3:PutObject"
      Resource  = "${aws_s3_bucket.alb_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
    }]
  })
}
