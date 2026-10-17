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
  type        = string
  description = "dev | stg | prod"
}

variable "consumidores" {
  description = "Un consumidor = una cola propia + una regla con su patrón"
  type = map(object({
    patron_detail   = any
    max_recepciones = optional(number, 5)
  }))
  default = {
    facturacion    = { patron_detail = {} }
    notificaciones = { patron_detail = {} }
    logistica      = { patron_detail = { envio = [{ prefix = "dom" }] } }
  }
}

# --- Bus del dominio y archivo para reproducir ---
resource "aws_cloudwatch_event_bus" "ordenes" {
  name = "${var.entorno}-ordenes"
}

resource "aws_cloudwatch_event_archive" "ordenes" {
  name             = "${var.entorno}-ordenes"
  event_source_arn = aws_cloudwatch_event_bus.ordenes.arn
  retention_days   = 30
  event_pattern    = jsonencode({ source = ["modalima.pedidos"] })
}

# --- Una regla por consumidor ---
resource "aws_cloudwatch_event_rule" "consumidor" {
  for_each       = var.consumidores
  name           = "${var.entorno}-pedido-creado-${each.key}"
  event_bus_name = aws_cloudwatch_event_bus.ordenes.name
  event_pattern = jsonencode(merge(
    {
      source        = ["modalima.pedidos"]
      "detail-type" = ["PedidoCreado"]
    },
    length(keys(each.value.patron_detail)) > 0 ? { detail = each.value.patron_detail } : {}
  ))
}

# --- Cola + DLQ por consumidor ---
resource "aws_sqs_queue" "dlq" {
  for_each                  = var.consumidores
  name                      = "${var.entorno}-${each.key}-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "cola" {
  for_each                   = var.consumidores
  name                       = "${var.entorno}-${each.key}"
  visibility_timeout_seconds = 120
  sqs_managed_sse_enabled    = true
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[each.key].arn
    maxReceiveCount     = each.value.max_recepciones
  })
}

data "aws_iam_policy_document" "cola" {
  for_each = var.consumidores
  statement {
    sid       = "SoloEventBridgeDeEstaRegla"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.cola[each.key].arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.consumidor[each.key].arn]
    }
  }
}

resource "aws_sqs_queue_policy" "cola" {
  for_each  = var.consumidores
  queue_url = aws_sqs_queue.cola[each.key].id
  policy    = data.aws_iam_policy_document.cola[each.key].json
}

resource "aws_cloudwatch_event_target" "cola" {
  for_each       = var.consumidores
  rule           = aws_cloudwatch_event_rule.consumidor[each.key].name
  event_bus_name = aws_cloudwatch_event_bus.ordenes.name
  target_id      = "sqs"
  arn            = aws_sqs_queue.cola[each.key].arn
}

# --- Bandeja de entrada (idempotencia del consumidor) ---
resource "aws_dynamodb_table" "bandeja_entrada" {
  name         = "${var.entorno}-bandeja-entrada"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "idMensaje"

  attribute {
    name = "idMensaje"
    type = "S"
  }

  ttl {
    attribute_name = "expira"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }
}

# --- Alarmas: lo que envejece y lo que cae a la DLQ ---
resource "aws_cloudwatch_metric_alarm" "dlq" {
  for_each            = var.consumidores
  alarm_name          = "${var.entorno}-${each.key}-dlq-con-mensajes"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.dlq[each.key].name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "antiguedad" {
  for_each            = var.consumidores
  alarm_name          = "${var.entorno}-${each.key}-mensaje-viejo"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateAgeOfOldestMessage"
  dimensions          = { QueueName = aws_sqs_queue.cola[each.key].name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  threshold           = 300
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
}

# --- Permisos mínimos por rol ---
data "aws_iam_policy_document" "publicador" {
  statement {
    actions   = ["events:PutEvents"]
    resources = [aws_cloudwatch_event_bus.ordenes.arn]
  }
}

resource "aws_iam_policy" "publicador" {
  name   = "${var.entorno}-publicador-pedidos"
  policy = data.aws_iam_policy_document.publicador.json
}

data "aws_iam_policy_document" "consumidor" {
  for_each = var.consumidores
  statement {
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:ChangeMessageVisibility", "sqs:GetQueueAttributes"]
    resources = [aws_sqs_queue.cola[each.key].arn]
  }
  statement {
    actions   = ["dynamodb:PutItem", "dynamodb:UpdateItem"]
    resources = [aws_dynamodb_table.bandeja_entrada.arn]
  }
}

resource "aws_iam_policy" "consumidor" {
  for_each = var.consumidores
  name     = "${var.entorno}-consumidor-${each.key}"
  policy   = data.aws_iam_policy_document.consumidor[each.key].json
}

output "bus" {
  value = aws_cloudwatch_event_bus.ordenes.name
}

output "colas" {
  value = { for k, q in aws_sqs_queue.cola : k => q.url }
}
