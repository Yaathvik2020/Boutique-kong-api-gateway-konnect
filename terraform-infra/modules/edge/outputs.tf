output "certificate_arn" {
  description = "Validated ACM certificate for api_hostname"
  value       = aws_acm_certificate_validation.api.certificate_arn
}

output "waf_acl_arn" {
  value = aws_wafv2_web_acl.this.arn
}

output "alb_logs_bucket" {
  value = aws_s3_bucket.alb_logs.bucket
}

output "route53_zone_id" {
  value = data.aws_route53_zone.this.zone_id
}

output "route53_zone_arn" {
  value = data.aws_route53_zone.this.arn
}
