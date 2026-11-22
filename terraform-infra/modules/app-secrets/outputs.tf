output "app_secret_name" {
  value = aws_secretsmanager_secret.app.name
}

output "konnect_cert_secret_name" {
  value = aws_secretsmanager_secret.konnect_cert.name
}

output "redis_secret_name" {
  value = aws_secretsmanager_secret.redis.name
}

output "redis_secret_arn" {
  value = aws_secretsmanager_secret.redis.arn
}
