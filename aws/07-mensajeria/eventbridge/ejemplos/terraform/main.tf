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

variable "bucket_cargas" {
  type        = string
  description = "Bucket de Café Andino con eventos hacia EventBridge activados"
}

variable "cuentas_productoras" {
  type        = list(string)
  default     = []
  description = "Cuentas que pueden publicar en el bus (vacío = solo esta cuenta)"
}

data "aws_caller_identity" "actual" {}

# --- Bus por dominio y archivo para reproducir ---
resource "aws_cloudwatch_event_bus" "ordenes" {
  name = "${var.entorno}-ordenes"
}

resource "aws_cloudwatch_event_archive" "ordenes" {
  name             = "${var.entorno}-ordenes"
  event_source_arn = aws_cloudwatch_event_bus.ordenes.arn
  retention_days   = 30
  event_pattern = jsonencode({
    source = ["modalima.ordenes"]
  })
}

# --- Otras cuentas autorizadas a publicar (solo PutEvents) ---
data "aws_iam_policy_document" "bus" {
  count = length(var.cuentas_productoras) > 0 ? 1 : 0
  statement {
    sid       = "PublicarDesdeCuentasConocidas"
    actions   = ["events:PutEvents"]
    resources = [aws_cloudwatch_event_bus.ordenes.arn]
    principals {
      type        = "AWS"
      identifiers = [for c in var.cuentas_productoras : "arn:aws:iam::${c}:root"]
    }
  }
}

resource "aws_cloudwatch_event_bus_policy" "ordenes" {
  count          = length(var.cuentas_productoras) > 0 ? 1 : 0
  event_bus_name = aws_cloudwatch_event_bus.ordenes.name
  policy         = data.aws_iam_policy_document.bus[0].json
}

# --- Reglas ---
resource "aws_cloudwatch_event_rule" "facturacion" {
  name           = "${var.entorno}-orden-grande"
  event_bus_name = aws_cloudwatch_event_bus.ordenes.name
  event_pattern = jsonencode({
    source        = ["modalima.ordenes"]
    "detail-type" = ["OrdenCreada"]
    detail = {
      total = [{ numeric = [">", 100] }]
    }
  })
}

resource "aws_cloudwatch_event_rule" "logistica" {
  name           = "${var.entorno}-orden-a-domicilio"
  event_bus_name = aws_cloudwatch_event_bus.ordenes.name
  event_pattern = jsonencode({
    source        = ["modalima.ordenes"]
    "detail-type" = ["OrdenCreada"]
    detail = {
      envio = [{ prefix = "dom" }]
    }
  })
}

# Bus predeterminado: evento de S3 "Object Created" del bucket de cargas
resource "aws_cloudwatch_event_rule" "cargas" {
  name = "${var.entorno}-carga-recibida"
  event_pattern = jsonencode({
    source        = ["aws.s3"]
    "detail-type" = ["Object Created"]
    detail = {
      bucket = { name = [var.bucket_cargas] }
    }
  })
}

# --- Colas destino (una por consumidor) y DLQ compartida de los destinos ---
locals {
  destinos = {
    facturacion  = aws_cloudwatch_event_rule.facturacion.arn
    logistica    = aws_cloudwatch_event_rule.logistica.arn
    verificacion = aws_cloudwatch_event_rule.cargas.arn
  }
}

resource "aws_sqs_queue" "cola" {
  for_each                   = local.destinos
  name                       = "${var.entorno}-eb-${each.key}"
  visibility_timeout_seconds = 120
  receive_wait_time_seconds  = 20
  sqs_managed_sse_enabled    = true
}

data "aws_iam_policy_document" "cola" {
  for_each = local.destinos
  statement {
    sid       = "EventBridgeEnvia"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.cola[each.key].arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [each.value]
    }
  }
}

resource "aws_sqs_queue_policy" "cola" {
  for_each  = local.destinos
  queue_url = aws_sqs_queue.cola[each.key].id
  policy    = data.aws_iam_policy_document.cola[each.key].json
}

resource "aws_sqs_queue" "fallidos" {
  name                      = "${var.entorno}-eb-fallidos"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
}

data "aws_iam_policy_document" "fallidos" {
  statement {
    sid       = "EventBridgeDejaFallidos"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.fallidos.arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:events:${var.region}:${data.aws_caller_identity.actual.account_id}:rule/*"]
    }
  }
}

resource "aws_sqs_queue_policy" "fallidos" {
  queue_url = aws_sqs_queue.fallidos.id
  policy    = data.aws_iam_policy_document.fallidos.json
}

# --- Destinos ---
resource "aws_cloudwatch_event_target" "facturacion" {
  rule           = aws_cloudwatch_event_rule.facturacion.name
  event_bus_name = aws_cloudwatch_event_bus.ordenes.name
  target_id      = "cola-facturacion"
  arn            = aws_sqs_queue.cola["facturacion"].arn

  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 10
  }
  dead_letter_config {
    arn = aws_sqs_queue.fallidos.arn
  }
}

# Logística recibe solo lo que necesita (transformador de entrada)
resource "aws_cloudwatch_event_target" "logistica" {
  rule           = aws_cloudwatch_event_rule.logistica.name
  event_bus_name = aws_cloudwatch_event_bus.ordenes.name
  target_id      = "cola-logistica"
  arn            = aws_sqs_queue.cola["logistica"].arn

  input_transformer {
    input_paths = {
      id        = "$.detail.idOrden"
      direccion = "$.detail.direccion"
      cuando    = "$.time"
    }
    input_template = "{\"idOrden\": \"<id>\", \"direccion\": \"<direccion>\", \"emitido\": \"<cuando>\"}"
  }
  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 10
  }
  dead_letter_config {
    arn = aws_sqs_queue.fallidos.arn
  }
}

resource "aws_cloudwatch_event_target" "verificacion" {
  rule      = aws_cloudwatch_event_rule.cargas.name
  target_id = "cola-verificacion"
  arn       = aws_sqs_queue.cola["verificacion"].arn

  dead_letter_config {
    arn = aws_sqs_queue.fallidos.arn
  }
}

# --- Scheduler: cierre de caja a las 23:00 hora de Lima ---
resource "aws_iam_role" "scheduler" {
  name = "${var.entorno}-scheduler-cierre"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "scheduler" {
  name = "enviar-a-cola"
  role = aws_iam_role.scheduler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sqs:SendMessage"
      Resource = aws_sqs_queue.cola["facturacion"].arn
    }]
  })
}

resource "aws_scheduler_schedule" "cierre_de_caja" {
  name                         = "${var.entorno}-cierre-de-caja"
  schedule_expression          = "cron(0 23 * * ? *)"
  schedule_expression_timezone = "America/Lima"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_sqs_queue.cola["facturacion"].arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ tipo = "CierreDeCaja", version = 1 })
  }
}

# --- Permiso mínimo del productor ---
data "aws_iam_policy_document" "productor" {
  statement {
    actions   = ["events:PutEvents"]
    resources = [aws_cloudwatch_event_bus.ordenes.arn]
  }
}

output "bus_arn" {
  value = aws_cloudwatch_event_bus.ordenes.arn
}

output "politica_productor_json" {
  value = data.aws_iam_policy_document.productor.json
}
