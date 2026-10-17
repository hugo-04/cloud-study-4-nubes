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

variable "subnet_ids" {
  type        = list(string)
  description = "Subredes privadas en al menos dos zonas"
}

variable "sg_clientes" {
  type        = string
  description = "Grupo de seguridad de los servicios que usan la base"
}

variable "motor_version" {
  type        = string
  default     = "16.6"
  description = "Versión de Aurora PostgreSQL (verifica las vigentes)"
}

variable "serverless_v2" {
  type        = bool
  default     = false
  description = "true = capacidad elástica (ACU); false = instancias provisionadas"
}

resource "aws_kms_key" "db" {
  description         = "Cifrado de la base ${var.entorno}"
  enable_key_rotation = true
}

resource "aws_db_subnet_group" "db" {
  name       = "${var.entorno}-pedidos"
  subnet_ids = var.subnet_ids
}

resource "aws_security_group" "db" {
  name        = "${var.entorno}-pedidos-db"
  description = "PostgreSQL solo desde los servicios"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "desde_clientes" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = var.sg_clientes
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "Servicios de la aplicación"
}

# TLS obligatorio y registro de consultas lentas
resource "aws_rds_cluster_parameter_group" "pg" {
  name        = "${var.entorno}-pedidos-pg16"
  family      = "aurora-postgresql16"
  description = "Parámetros de ${var.entorno}"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
  parameter {
    name  = "log_min_duration_statement"
    value = "500"
  }
}

resource "aws_rds_cluster" "pedidos" {
  cluster_identifier = "${var.entorno}-pedidos"
  engine             = "aurora-postgresql"
  engine_version     = var.motor_version
  database_name      = "pedidos"
  master_username    = "admin_pedidos"

  # La contraseña la crea y rota RDS en Secrets Manager (nunca pasa por Terraform)
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.db.key_id

  db_subnet_group_name            = aws_db_subnet_group.db.name
  vpc_security_group_ids          = [aws_security_group.db.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.pg.name

  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.db.arn
  iam_database_authentication_enabled = true

  backup_retention_period      = 14
  preferred_backup_window      = "07:00-08:00"
  preferred_maintenance_window = "sun:08:30-sun:09:30"
  copy_tags_to_snapshot        = true

  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.entorno}-pedidos-final"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  dynamic "serverlessv2_scaling_configuration" {
    for_each = var.serverless_v2 ? [1] : []
    content {
      min_capacity = 0.5
      max_capacity = 8
    }
  }
}

# Un escritor y un lector (en otra zona, el lector se promueve si cae el escritor)
resource "aws_rds_cluster_instance" "nodo" {
  count              = 2
  identifier         = "${var.entorno}-pedidos-${count.index}"
  cluster_identifier = aws_rds_cluster.pedidos.id
  engine             = aws_rds_cluster.pedidos.engine
  engine_version     = aws_rds_cluster.pedidos.engine_version
  instance_class     = var.serverless_v2 ? "db.serverless" : "db.r6g.large"
  promotion_tier     = count.index

  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.db.arn
  auto_minor_version_upgrade      = true
}

# --- RDS Proxy: reutiliza conexiones y suaviza el failover ---
data "aws_iam_policy_document" "proxy_confianza" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "proxy_permisos" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_rds_cluster.pedidos.master_user_secret[0].secret_arn]
  }
  statement {
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.db.arn]
  }
}

resource "aws_iam_role" "proxy" {
  name               = "${var.entorno}-pedidos-proxy"
  assume_role_policy = data.aws_iam_policy_document.proxy_confianza.json
}

resource "aws_iam_role_policy" "proxy" {
  name   = "leer-secreto"
  role   = aws_iam_role.proxy.id
  policy = data.aws_iam_policy_document.proxy_permisos.json
}

resource "aws_db_proxy" "pedidos" {
  name                   = "${var.entorno}-pedidos"
  engine_family          = "POSTGRESQL"
  role_arn               = aws_iam_role.proxy.arn
  vpc_subnet_ids         = var.subnet_ids
  vpc_security_group_ids = [aws_security_group.db.id]
  require_tls            = true
  idle_client_timeout    = 1800

  auth {
    auth_scheme = "SECRETS"
    iam_auth    = "REQUIRED"
    secret_arn  = aws_rds_cluster.pedidos.master_user_secret[0].secret_arn
  }
}

resource "aws_db_proxy_default_target_group" "pedidos" {
  db_proxy_name = aws_db_proxy.pedidos.name

  connection_pool_config {
    max_connections_percent      = 80
    max_idle_connections_percent = 20
    connection_borrow_timeout    = 30
  }
}

resource "aws_db_proxy_target" "pedidos" {
  db_proxy_name         = aws_db_proxy.pedidos.name
  target_group_name     = aws_db_proxy_default_target_group.pedidos.name
  db_cluster_identifier = aws_rds_cluster.pedidos.id
}

# --- Alarmas ---
resource "aws_cloudwatch_metric_alarm" "cpu" {
  alarm_name          = "${var.entorno}-pedidos-cpu"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = { DBClusterIdentifier = aws_rds_cluster.pedidos.cluster_identifier }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "conexiones" {
  alarm_name          = "${var.entorno}-pedidos-conexiones"
  namespace           = "AWS/RDS"
  metric_name         = "DatabaseConnections"
  dimensions          = { DBClusterIdentifier = aws_rds_cluster.pedidos.cluster_identifier }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  threshold           = 400
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "lag" {
  alarm_name          = "${var.entorno}-pedidos-lag-replica"
  namespace           = "AWS/RDS"
  metric_name         = "AuroraReplicaLag"
  dimensions          = { DBClusterIdentifier = aws_rds_cluster.pedidos.cluster_identifier }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  threshold           = 1000
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
}

output "endpoint_escritor" {
  value = aws_rds_cluster.pedidos.endpoint
}

output "endpoint_lector" {
  value = aws_rds_cluster.pedidos.reader_endpoint
}

output "endpoint_proxy" {
  value = aws_db_proxy.pedidos.endpoint
}

output "id_recurso_cluster" {
  description = "Va en el ARN rds-db:connect de la política IAM"
  value       = aws_rds_cluster.pedidos.cluster_resource_id
}
