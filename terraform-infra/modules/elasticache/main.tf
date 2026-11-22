# ElastiCache Redis: one shared counter store for Kong's rate-limiting-advanced plugin,
# so "300 requests/min" means 300 in total, however many Kong pods are running.
#   - Database subnets only, reachable only from the EKS cluster
#   - TLS in transit + encryption at rest + password (AUTH token)
#   - nodes > 1 = replica in another AZ with automatic failover (prod)
terraform {
  required_providers {
    aws    = { source = "hashicorp/aws" }
    random = { source = "hashicorp/random" }
  }
}

resource "random_password" "auth" {
  length  = 40
  special = false # ElastiCache AUTH tokens can't contain @ " / and are safer without symbols
}

resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.name}-redis"
  subnet_ids = var.subnet_ids
}

resource "aws_security_group" "this" {
  name        = "${var.name}-redis"
  description = "Redis from the EKS cluster only (Kong data planes)"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Redis TLS from EKS nodes/pods"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [var.allowed_security_group_id]
  }

  tags = { Name = "${var.name}-redis" }
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.name}-rl"
  description          = "Kong rate limiting counters (${var.name})"

  engine               = "redis"
  engine_version       = var.engine_version
  parameter_group_name = var.parameter_group_name
  node_type            = var.node_type
  port                 = 6379

  num_cache_clusters         = var.nodes
  automatic_failover_enabled = var.nodes > 1
  multi_az_enabled           = var.nodes > 1

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.this.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = random_password.auth.result

  snapshot_retention_limit   = var.snapshot_retention_days # counters are short-lived; 0 is fine
  maintenance_window         = "sun:22:00-sun:23:00"       # UTC
  apply_immediately          = false
  auto_minor_version_upgrade = true
}
