terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "entorno" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subredes_privadas" {
  type = list(string)
}

variable "sg_aplicacion" {
  type        = string
  description = "Grupo de seguridad de la aplicación (único origen permitido)"
}

variable "password_app" {
  type        = string
  sensitive   = true
  description = "Contraseña del usuario de la aplicación. OJO: queda en el estado (usa estado remoto cifrado) o crea el usuario fuera de Terraform"
}

resource "aws_kms_key" "cache" {
  description         = "Cifrado en reposo de ElastiCache ${var.entorno}"
  enable_key_rotation = true
}

resource "aws_security_group" "cache" {
  name        = "${var.entorno}-cache"
  description = "ElastiCache: solo desde la aplicacion"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "desde_app" {
  security_group_id            = aws_security_group.cache.id
  referenced_security_group_id = var.sg_aplicacion
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  description                  = "Valkey/Redis desde la aplicacion"
}

resource "aws_elasticache_subnet_group" "cache" {
  name       = "${var.entorno}-cache"
  subnet_ids = var.subredes_privadas
}

# Caché: al llenarse, expulsa lo menos usado; expira conexiones ociosas
resource "aws_elasticache_parameter_group" "cache" {
  name   = "${var.entorno}-cache-valkey8"
  family = "valkey8"

  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }
}

# --- Usuarios (RBAC): "default" desactivado y un usuario de aplicación acotado a su prefijo ---
resource "aws_elasticache_user" "default_apagado" {
  user_id       = "${var.entorno}-default"
  user_name     = "default"
  engine        = "VALKEY"
  access_string = "off ~* -@all"

  authentication_mode {
    type = "no-password-required"
  }
}

resource "aws_elasticache_user" "app" {
  user_id       = "${var.entorno}-app"
  user_name     = "app"
  engine        = "VALKEY"
  access_string = "on ~app:${var.entorno}:* &* +@all -@dangerous"

  authentication_mode {
    type      = "password"
    passwords = [var.password_app]
  }
}

resource "aws_elasticache_user_group" "cache" {
  engine        = "VALKEY"
  user_group_id = "${var.entorno}-cache"
  user_ids      = [aws_elasticache_user.default_apagado.user_id, aws_elasticache_user.app.user_id]
}

# --- Grupo de replicación: 1 primario + 2 réplicas en distintas zonas, failover automático ---
resource "aws_elasticache_replication_group" "cache" {
  replication_group_id = "${var.entorno}-cache"
  description          = "Cache y sesiones ${var.entorno}"

  engine               = "valkey"
  engine_version       = "8.0"
  node_type            = "cache.r7g.large"
  port                 = 6379
  parameter_group_name = aws_elasticache_parameter_group.cache.name

  # Modo clúster deshabilitado: un shard. Para modo clúster: num_node_groups y replicas_per_node_group.
  num_cache_clusters         = 3
  automatic_failover_enabled = true
  multi_az_enabled           = true

  subnet_group_name  = aws_elasticache_subnet_group.cache.name
  security_group_ids = [aws_security_group.cache.id]

  at_rest_encryption_enabled = true
  kms_key_id                 = aws_kms_key.cache.arn
  transit_encryption_enabled = true
  user_group_ids             = [aws_elasticache_user_group.cache.user_group_id]

  snapshot_retention_limit   = 3
  snapshot_window            = "06:00-07:00"
  maintenance_window         = "sun:07:30-sun:08:30"
  auto_minor_version_upgrade = true
}

# --- Alternativa sin nodos que elegir: caché serverless ---
resource "aws_elasticache_serverless_cache" "sesiones" {
  name                 = "${var.entorno}-sesiones"
  engine               = "valkey"
  major_engine_version = "8"
  description          = "Sesiones efimeras ${var.entorno}"

  cache_usage_limits {
    data_storage {
      maximum = 10
      unit    = "GB"
    }
    ecpu_per_second {
      maximum = 20000
    }
  }

  kms_key_id               = aws_kms_key.cache.arn
  security_group_ids       = [aws_security_group.cache.id]
  subnet_ids               = var.subredes_privadas
  snapshot_retention_limit = 1
}

# --- Alarmas ---
resource "aws_cloudwatch_metric_alarm" "memoria" {
  alarm_name          = "${var.entorno}-cache-memoria-alta"
  namespace           = "AWS/ElastiCache"
  metric_name         = "DatabaseMemoryUsagePercentage"
  dimensions          = { ReplicationGroupId = aws_elasticache_replication_group.cache.replication_group_id }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 3
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
}

resource "aws_cloudwatch_metric_alarm" "expulsiones" {
  alarm_name          = "${var.entorno}-cache-expulsiones"
  namespace           = "AWS/ElastiCache"
  metric_name         = "Evictions"
  dimensions          = { ReplicationGroupId = aws_elasticache_replication_group.cache.replication_group_id }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 2
  threshold           = 100
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "cpu_motor" {
  alarm_name          = "${var.entorno}-cache-cpu-motor"
  namespace           = "AWS/ElastiCache"
  metric_name         = "EngineCPUUtilization"
  dimensions          = { ReplicationGroupId = aws_elasticache_replication_group.cache.replication_group_id }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 3
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
}

output "endpoint_primario" {
  value = aws_elasticache_replication_group.cache.primary_endpoint_address
}

output "endpoint_lectura" {
  value = aws_elasticache_replication_group.cache.reader_endpoint_address
}

output "endpoint_serverless" {
  value = aws_elasticache_serverless_cache.sesiones.endpoint
}
