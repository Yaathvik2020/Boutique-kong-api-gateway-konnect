output "host" {
  description = "Primary endpoint (TLS)"
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "port" {
  value = aws_elasticache_replication_group.this.port
}

output "password" {
  value     = random_password.auth.result
  sensitive = true
}
