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

variable "route_table_ids" {
  type        = list(string)
  description = "Tablas de rutas de las subredes privadas (para el endpoint de pasarela)"
}

resource "aws_kms_key" "dynamo" {
  description         = "Cifrado de las tablas ${var.entorno}"
  enable_key_rotation = true
}

# --- Tabla principal: pedidos y clientes (una sola tabla), bajo demanda ---
resource "aws_dynamodb_table" "pedidos" {
  name         = "${var.entorno}-pedidos"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"
  range_key    = "sk"

  attribute {
    name = "pk"
    type = "S"
  }
  attribute {
    name = "sk"
    type = "S"
  }
  attribute {
    name = "gsi1pk"
    type = "S"
  }
  attribute {
    name = "gsi1sk"
    type = "S"
  }

  global_secondary_index {
    name               = "gsi1"
    hash_key           = "gsi1pk"
    range_key          = "gsi1sk"
    projection_type    = "INCLUDE"
    non_key_attributes = ["total", "cliente"]
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamo.arn
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  deletion_protection_enabled = true
}

# --- Idempotencia: PutItem condicional + TTL de limpieza ---
resource "aws_dynamodb_table" "idempotencia" {
  name         = "${var.entorno}-idempotencia"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"

  attribute {
    name = "pk"
    type = "S"
  }

  ttl {
    attribute_name = "expira_en"
    enabled        = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamo.arn
  }
}

# --- Catálogo: aprovisionado con auto scaling (carga estable y conocida) ---
resource "aws_dynamodb_table" "catalogo" {
  name           = "${var.entorno}-catalogo"
  billing_mode   = "PROVISIONED"
  read_capacity  = 20
  write_capacity = 5
  hash_key       = "pk"

  attribute {
    name = "pk"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  lifecycle {
    ignore_changes = [read_capacity, write_capacity]
  }
}

resource "aws_appautoscaling_target" "catalogo_lectura" {
  service_namespace  = "dynamodb"
  resource_id        = "table/${aws_dynamodb_table.catalogo.name}"
  scalable_dimension = "dynamodb:table:ReadCapacityUnits"
  min_capacity       = 20
  max_capacity       = 400
}

resource "aws_appautoscaling_policy" "catalogo_lectura" {
  name               = "${var.entorno}-catalogo-lectura"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.catalogo_lectura.service_namespace
  resource_id        = aws_appautoscaling_target.catalogo_lectura.resource_id
  scalable_dimension = aws_appautoscaling_target.catalogo_lectura.scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value = 70
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBReadCapacityUtilization"
    }
  }
}

# --- Endpoint de pasarela: el tráfico a DynamoDB no sale a Internet (sin costo por hora) ---
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.route_table_ids
}

# --- Permisos del servicio de órdenes (tabla e índices) ---
data "aws_iam_policy_document" "servicio" {
  statement {
    actions = [
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:BatchWriteItem",
      "dynamodb:BatchGetItem",
    ]
    resources = [aws_dynamodb_table.pedidos.arn, "${aws_dynamodb_table.pedidos.arn}/index/*"]
  }
  statement {
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.idempotencia.arn]
  }
  statement {
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.dynamo.arn]
  }
}

# --- Alarmas ---
resource "aws_cloudwatch_metric_alarm" "escritura_limitada" {
  alarm_name          = "${var.entorno}-pedidos-escritura-limitada"
  namespace           = "AWS/DynamoDB"
  metric_name         = "WriteThrottleEvents"
  dimensions          = { TableName = aws_dynamodb_table.pedidos.name }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "errores_sistema" {
  alarm_name          = "${var.entorno}-pedidos-errores-sistema"
  namespace           = "AWS/DynamoDB"
  metric_name         = "SystemErrors"
  dimensions          = { TableName = aws_dynamodb_table.pedidos.name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
}

output "tabla_pedidos_arn" {
  value = aws_dynamodb_table.pedidos.arn
}

output "stream_pedidos_arn" {
  value = aws_dynamodb_table.pedidos.stream_arn
}

output "politica_servicio_json" {
  value = data.aws_iam_policy_document.servicio.json
}
