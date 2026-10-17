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

variable "tema_sns_arn" {
  type        = string
  default     = ""
  description = "Si se indica, la cola acepta mensajes SOLO de este tópico SNS"
}

resource "aws_sqs_queue" "dlq" {
  name                      = "${var.entorno}-ordenes-dlq"
  message_retention_seconds = 1209600 # 14 días: mayor que la principal
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "ordenes" {
  name                       = "${var.entorno}-ordenes"
  visibility_timeout_seconds = 360 # 6x el trabajo típico de 60 s
  receive_wait_time_seconds  = 20  # long polling por defecto
  message_retention_seconds  = 345600
  max_message_size           = 1048576
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 5
  })
}

# Cola FIFO para cambios de estado de pedidos (orden por pedido)
resource "aws_sqs_queue" "estado_fifo" {
  name                        = "${var.entorno}-estado-pedido.fifo"
  fifo_queue                  = true
  content_based_deduplication = false
  deduplication_scope         = "messageGroup"
  fifo_throughput_limit       = "perMessageGroupId"
  visibility_timeout_seconds  = 120
  sqs_managed_sse_enabled     = true
}

data "aws_iam_policy_document" "ordenes" {
  statement {
    sid       = "SoloTLS"
    effect    = "Deny"
    actions   = ["sqs:*"]
    resources = [aws_sqs_queue.ordenes.arn]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  dynamic "statement" {
    for_each = var.tema_sns_arn == "" ? [] : [1]
    content {
      sid       = "PermitirSoloMiTopico"
      actions   = ["sqs:SendMessage"]
      resources = [aws_sqs_queue.ordenes.arn]
      principals {
        type        = "Service"
        identifiers = ["sns.amazonaws.com"]
      }
      condition {
        test     = "ArnEquals"
        variable = "aws:SourceArn"
        values   = [var.tema_sns_arn]
      }
    }
  }
}

resource "aws_sqs_queue_policy" "ordenes" {
  queue_url = aws_sqs_queue.ordenes.id
  policy    = data.aws_iam_policy_document.ordenes.json
}

# Alarmas: DLQ con mensajes y antigüedad del mensaje más viejo
resource "aws_cloudwatch_metric_alarm" "dlq" {
  alarm_name          = "${var.entorno}-ordenes-dlq-con-mensajes"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.dlq.name }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "antiguedad" {
  alarm_name          = "${var.entorno}-ordenes-mensaje-viejo"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateAgeOfOldestMessage"
  dimensions          = { QueueName = aws_sqs_queue.ordenes.name }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 2
  threshold           = 900
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
}

data "aws_iam_policy_document" "productor" {
  statement {
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.ordenes.arn]
  }
}

data "aws_iam_policy_document" "consumidor" {
  statement {
    actions = [
      "sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:ChangeMessageVisibility", "sqs:GetQueueAttributes",
    ]
    resources = [aws_sqs_queue.ordenes.arn]
  }
}

output "cola_url" {
  value = aws_sqs_queue.ordenes.url
}

output "dlq_arn" {
  value = aws_sqs_queue.dlq.arn
}

output "productor_policy_json" {
  value = data.aws_iam_policy_document.productor.json
}

output "consumidor_policy_json" {
  value = data.aws_iam_policy_document.consumidor.json
}
