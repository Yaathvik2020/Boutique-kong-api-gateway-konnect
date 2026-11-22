# Amazon RDS PostgreSQL for the boutique databases (staging/prod).
#   - Database subnets only (no internet route), reachable only from the EKS nodes
#   - Encrypted, forced SSL, automated backups, Multi-AZ optional
#   - The master password is generated here and stored in Secrets Manager by
#     the app-secrets module (never in Git or tfvars)
terraform {
  required_providers {
    aws    = { source = "hashicorp/aws" }
    random = { source = "hashicorp/random" }
  }
}

resource "random_password" "master" {
  length  = 32
  special = false # safe inside postgresql:// URLs
}

resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.database_subnet_ids
}

resource "aws_security_group" "this" {
  name        = "${var.name}-rds"
  description = "Postgres from the EKS cluster only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Postgres from EKS nodes/pods"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.allowed_security_group_id]
  }

  tags = { Name = "${var.name}-rds" }
}

resource "aws_db_parameter_group" "this" {
  name   = "${var.name}-pg${var.engine_major_version}"
  family = "postgres${var.engine_major_version}"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000" # log queries slower than 1 s
  }
}

resource "aws_db_instance" "this" {
  identifier     = var.name
  engine         = "postgres"
  engine_version = var.engine_major_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  username = var.master_username
  password = random_password.master.result
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false
  multi_az               = var.multi_az

  backup_retention_period    = var.backup_retention_days
  backup_window              = "20:00-21:00"         # UTC = 01:30-02:30 IST
  maintenance_window         = "sun:21:30-sun:22:30" # UTC
  copy_tags_to_snapshot      = true
  auto_minor_version_upgrade = true

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = !var.deletion_protection
  final_snapshot_identifier = "${var.name}-final"

  performance_insights_enabled    = true
  enabled_cloudwatch_logs_exports = ["postgresql"]
}
