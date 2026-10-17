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

variable "vpc_id" {
  type = string
}

variable "eni_app_id" {
  description = "ENI de referencia de la aplicación (origen del análisis guardado)."
  type        = string
}

variable "eni_base_id" {
  description = "ENI de la base de datos (destino)."
  type        = string
}

variable "retencion_dias" {
  type    = number
  default = 30
}

variable "umbral_rechazos" {
  description = "Rechazos por 5 minutos que disparan la alarma."
  type        = number
  default     = 500
}

# ---------- Análisis guardado para la ruta crítica app -> base:5432 ----------
resource "aws_ec2_network_insights_path" "app_a_base" {
  source           = var.eni_app_id
  destination      = var.eni_base_id
  protocol         = "tcp"
  destination_port = 5432
  tags             = { Name = "app-a-base-5432" }
}

# ---------- Flow Logs a CloudWatch con formato personalizado ----------
resource "aws_cloudwatch_log_group" "flow" {
  name              = "/vpc/flowlogs/${var.vpc_id}"
  retention_in_days = var.retencion_dias
}

data "aws_iam_policy_document" "confianza" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "escritura" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = ["${aws_cloudwatch_log_group.flow.arn}:*"]
  }
}

resource "aws_iam_role" "flow" {
  name_prefix        = "flowlogs-"
  assume_role_policy = data.aws_iam_policy_document.confianza.json
}

resource "aws_iam_role_policy" "flow" {
  role   = aws_iam_role.flow.id
  policy = data.aws_iam_policy_document.escritura.json
}

resource "aws_flow_log" "vpc" {
  vpc_id               = var.vpc_id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow.arn
  iam_role_arn         = aws_iam_role.flow.arn

  # Formato personalizado: añade dirección real del paquete, sentido, AZ y banderas TCP
  log_format = "$${version} $${account-id} $${interface-id} $${srcaddr} $${dstaddr} $${srcport} $${dstport} $${protocol} $${packets} $${bytes} $${start} $${end} $${action} $${log-status} $${pkt-srcaddr} $${pkt-dstaddr} $${flow-direction} $${az-id} $${tcp-flags}"

  max_aggregation_interval = 60
}

# ---------- Alarma: demasiados rechazos ----------
resource "aws_cloudwatch_log_metric_filter" "rechazos" {
  name           = "rechazos-vpc"
  log_group_name = aws_cloudwatch_log_group.flow.name
  pattern        = "[version, account, eni, source, destination, srcport, destport, protocol, packets, bytes, start, end, action=\"REJECT\", status, ...]"

  metric_transformation {
    name      = "RechazosVpc"
    namespace = "Red/Diagnostico"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "rechazos" {
  alarm_name          = "vpc-rechazos-anomalos"
  namespace           = "Red/Diagnostico"
  metric_name         = "RechazosVpc"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.umbral_rechazos
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_description   = "Pico de tráfico rechazado en la VPC: revisar SG/NACL o un escaneo"
}

output "analisis_guardado" {
  value = aws_ec2_network_insights_path.app_a_base.id
}
