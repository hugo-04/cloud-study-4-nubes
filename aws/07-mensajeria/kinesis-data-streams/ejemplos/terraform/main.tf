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

variable "app_kcl" {
  type        = string
  default     = "analitica-kcl"
  description = "Nombre de la aplicación KCL (da nombre a la tabla de leases en DynamoDB)"
}

data "aws_caller_identity" "actual" {}

resource "aws_kms_key" "kinesis" {
  description         = "Clave de los streams ${var.entorno}"
  enable_key_rotation = true
}

# Clickstream: bajo demanda, retención de 48 h
resource "aws_kinesis_stream" "clics" {
  name             = "${var.entorno}-clics"
  retention_period = 48
  encryption_type  = "KMS"
  kms_key_id       = aws_kms_key.kinesis.id

  stream_mode_details {
    stream_mode = "ON_DEMAND"
  }

  shard_level_metrics = [
    "IncomingBytes",
    "IncomingRecords",
    "IteratorAgeMilliseconds",
    "WriteProvisionedThroughputExceeded",
  ]
}

# Órdenes: aprovisionado (carga estable y conocida), 2 shards
resource "aws_kinesis_stream" "ordenes" {
  name             = "${var.entorno}-ordenes"
  shard_count      = 2
  retention_period = 168
  encryption_type  = "KMS"
  kms_key_id       = aws_kms_key.kinesis.id

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }
}

# Fan-out mejorado para el consumidor crítico
resource "aws_kinesis_stream_consumer" "antifraude" {
  name       = "antifraude"
  stream_arn = aws_kinesis_stream.clics.arn
}

# --- Permisos mínimos ---
data "aws_iam_policy_document" "productor" {
  statement {
    actions   = ["kinesis:PutRecord", "kinesis:PutRecords"]
    resources = [aws_kinesis_stream.clics.arn]
  }
  statement {
    actions   = ["kms:GenerateDataKey"]
    resources = [aws_kms_key.kinesis.arn]
  }
}

data "aws_iam_policy_document" "consumidor_kcl" {
  statement {
    actions = [
      "kinesis:DescribeStream",
      "kinesis:DescribeStreamSummary",
      "kinesis:GetRecords",
      "kinesis:GetShardIterator",
      "kinesis:ListShards",
      "kinesis:SubscribeToShard",
    ]
    resources = [aws_kinesis_stream.clics.arn, "${aws_kinesis_stream.clics.arn}/consumer/*"]
  }
  statement {
    actions = [
      "dynamodb:CreateTable",
      "dynamodb:DescribeTable",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Scan",
      "dynamodb:Query",
      "dynamodb:UpdateTable",
    ]
    resources = ["arn:aws:dynamodb:${var.region}:${data.aws_caller_identity.actual.account_id}:table/${var.app_kcl}*"]
  }
  statement {
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]
  }
  statement {
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.kinesis.arn]
  }
}

# --- Alarmas: atraso del lector y throttling de escritura ---
resource "aws_cloudwatch_metric_alarm" "atraso" {
  alarm_name          = "${var.entorno}-clics-lector-atrasado"
  namespace           = "AWS/Kinesis"
  metric_name         = "GetRecords.IteratorAgeMilliseconds"
  dimensions          = { StreamName = aws_kinesis_stream.clics.name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  threshold           = 300000
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "throttling_ordenes" {
  alarm_name          = "${var.entorno}-ordenes-escritura-limitada"
  namespace           = "AWS/Kinesis"
  metric_name         = "WriteProvisionedThroughputExceeded"
  dimensions          = { StreamName = aws_kinesis_stream.ordenes.name }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
}

output "clics_arn" {
  value = aws_kinesis_stream.clics.arn
}

output "politica_productor_json" {
  value = data.aws_iam_policy_document.productor.json
}

output "politica_consumidor_json" {
  value = data.aws_iam_policy_document.consumidor_kcl.json
}
