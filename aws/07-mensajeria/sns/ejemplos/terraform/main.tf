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

resource "aws_kms_key" "sns" {
  description         = "Clave de los tópicos SNS ${var.entorno}"
  enable_key_rotation = true
}

resource "aws_sns_topic" "ordenes" {
  name              = "${var.entorno}-ordenes"
  kms_master_key_id = aws_kms_key.sns.id
}

# --- Suscriptor: facturación (solo pedidos de más de 100) ---
resource "aws_sqs_queue" "facturacion_dlq" {
  name                    = "${var.entorno}-facturacion-dlq"
  sqs_managed_sse_enabled = true
}

resource "aws_sqs_queue" "facturacion" {
  name                       = "${var.entorno}-facturacion"
  visibility_timeout_seconds = 120
  receive_wait_time_seconds  = 20
  sqs_managed_sse_enabled    = true
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.facturacion_dlq.arn
    maxReceiveCount     = 5
  })
}

# --- Suscriptor: logística (solo envíos a domicilio) ---
resource "aws_sqs_queue" "logistica" {
  name                       = "${var.entorno}-logistica"
  visibility_timeout_seconds = 120
  receive_wait_time_seconds  = 20
  sqs_managed_sse_enabled    = true
}

# --- Suscriptor: analítica (todo) ---
resource "aws_sqs_queue" "analitica" {
  name                      = "${var.entorno}-analitica"
  receive_wait_time_seconds = 20
  sqs_managed_sse_enabled   = true
}

# Cada cola autoriza SOLO a este tópico
data "aws_iam_policy_document" "desde_topico" {
  for_each = {
    facturacion = aws_sqs_queue.facturacion.arn
    logistica   = aws_sqs_queue.logistica.arn
    analitica   = aws_sqs_queue.analitica.arn
  }
  statement {
    actions   = ["sqs:SendMessage"]
    resources = [each.value]
    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_sns_topic.ordenes.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "facturacion" {
  queue_url = aws_sqs_queue.facturacion.id
  policy    = data.aws_iam_policy_document.desde_topico["facturacion"].json
}

resource "aws_sqs_queue_policy" "logistica" {
  queue_url = aws_sqs_queue.logistica.id
  policy    = data.aws_iam_policy_document.desde_topico["logistica"].json
}

resource "aws_sqs_queue_policy" "analitica" {
  queue_url = aws_sqs_queue.analitica.id
  policy    = data.aws_iam_policy_document.desde_topico["analitica"].json
}

# DLQ para entregas fallidas de la suscripción de facturación
resource "aws_sqs_queue" "suscripcion_dlq" {
  name                    = "${var.entorno}-ordenes-suscripcion-dlq"
  sqs_managed_sse_enabled = true
}

data "aws_iam_policy_document" "dlq_suscripcion" {
  statement {
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.suscripcion_dlq.arn]
    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_sns_topic.ordenes.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "suscripcion_dlq" {
  queue_url = aws_sqs_queue.suscripcion_dlq.id
  policy    = data.aws_iam_policy_document.dlq_suscripcion.json
}

resource "aws_sns_topic_subscription" "facturacion" {
  topic_arn            = aws_sns_topic.ordenes.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.facturacion.arn
  raw_message_delivery = true
  filter_policy_scope  = "MessageAttributes"
  filter_policy = jsonencode({
    tipo  = ["OrdenCreada"]
    total = [{ numeric = [">", 100] }]
  })
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.suscripcion_dlq.arn
  })
}

resource "aws_sns_topic_subscription" "logistica" {
  topic_arn            = aws_sns_topic.ordenes.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.logistica.arn
  raw_message_delivery = true
  filter_policy = jsonencode({
    envio = ["domicilio"]
  })
}

resource "aws_sns_topic_subscription" "analitica" {
  topic_arn            = aws_sns_topic.ordenes.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.analitica.arn
  raw_message_delivery = true
}

# El rol del productor puede publicar solo en este tópico (y usar la clave)
data "aws_iam_policy_document" "productor" {
  statement {
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.ordenes.arn]
  }
  statement {
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [aws_kms_key.sns.arn]
  }
}

resource "aws_iam_policy" "productor" {
  name   = "${var.entorno}-ordenes-productor"
  policy = data.aws_iam_policy_document.productor.json
}

output "topic_arn" {
  value = aws_sns_topic.ordenes.arn
}

output "productor_policy_arn" {
  value = aws_iam_policy.productor.arn
}
