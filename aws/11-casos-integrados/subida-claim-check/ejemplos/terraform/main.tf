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

variable "origen_web" {
  type        = string
  description = "Origen del navegador que sube (CORS), p. ej. https://tienda.modalima.example"
}

data "aws_caller_identity" "actual" {}

locals {
  sufijo = "${var.entorno}-${data.aws_caller_identity.actual.account_id}"
}

# --- Cuarentena: aquí aterriza TODO lo que sube el público, sin confiar en nada ---
resource "aws_s3_bucket" "cuarentena" {
  bucket = "modalima-cuarentena-${local.sufijo}"
}

resource "aws_s3_bucket_public_access_block" "cuarentena" {
  bucket                  = aws_s3_bucket.cuarentena.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cuarentena" {
  bucket = aws_s3_bucket.cuarentena.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_cors_configuration" "cuarentena" {
  bucket = aws_s3_bucket.cuarentena.id
  cors_rule {
    allowed_methods = ["PUT"]
    allowed_origins = [var.origen_web]
    allowed_headers = ["content-type", "content-length"]
    max_age_seconds = 600
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cuarentena" {
  bucket = aws_s3_bucket.cuarentena.id
  rule {
    id     = "limpiar-cuarentena"
    status = "Enabled"
    filter {
      prefix = "entrada/"
    }
    expiration {
      days = 1
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

resource "aws_s3_bucket_notification" "cuarentena" {
  bucket      = aws_s3_bucket.cuarentena.id
  eventbridge = true
}

# --- Validadas: solo lo que pasó los controles ---
resource "aws_s3_bucket" "validadas" {
  bucket = "modalima-validadas-${local.sufijo}"
}

resource "aws_s3_bucket_public_access_block" "validadas" {
  bucket                  = aws_s3_bucket.validadas.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "validadas" {
  bucket = aws_s3_bucket.validadas.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "validadas" {
  bucket = aws_s3_bucket.validadas.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "solo_tls" {
  for_each = {
    cuarentena = aws_s3_bucket.cuarentena.arn
    validadas  = aws_s3_bucket.validadas.arn
  }
  statement {
    sid       = "SoloTLS"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [each.value, "${each.value}/*"]
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
}

resource "aws_s3_bucket_policy" "cuarentena" {
  bucket = aws_s3_bucket.cuarentena.id
  policy = data.aws_iam_policy_document.solo_tls["cuarentena"].json
}

resource "aws_s3_bucket_policy" "validadas" {
  bucket = aws_s3_bucket.validadas.id
  policy = data.aws_iam_policy_document.solo_tls["validadas"].json
}

# --- Estado de cada carga ---
resource "aws_dynamodb_table" "cargas" {
  name         = "${var.entorno}-cargas"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
  attribute {
    name = "estado"
    type = "S"
  }
  attribute {
    name = "creada"
    type = "S"
  }

  global_secondary_index {
    name            = "por-estado"
    projection_type = "ALL"
    key_schema {
      attribute_name = "estado"
      key_type       = "HASH"
    }
    key_schema {
      attribute_name = "creada"
      key_type       = "RANGE"
    }
  }

  ttl {
    attribute_name = "expira"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }
}

# --- Aviso de subida: S3 -> EventBridge -> SQS ---
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.entorno}-validacion-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "validacion" {
  name                       = "${var.entorno}-validacion"
  visibility_timeout_seconds = 120
  sqs_managed_sse_enabled    = true
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 5
  })
}

resource "aws_cloudwatch_event_rule" "subida" {
  name = "${var.entorno}-carga-recibida"
  event_pattern = jsonencode({
    source        = ["aws.s3"]
    "detail-type" = ["Object Created"]
    detail = {
      bucket = { name = [aws_s3_bucket.cuarentena.bucket] }
      object = { key = [{ prefix = "entrada/" }] }
    }
  })
}

data "aws_iam_policy_document" "cola" {
  statement {
    sid       = "SoloEstaRegla"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.validacion.arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.subida.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "validacion" {
  queue_url = aws_sqs_queue.validacion.id
  policy    = data.aws_iam_policy_document.cola.json
}

resource "aws_cloudwatch_event_target" "subida" {
  rule      = aws_cloudwatch_event_rule.subida.name
  target_id = "sqs"
  arn       = aws_sqs_queue.validacion.arn
}

resource "aws_cloudwatch_metric_alarm" "dlq" {
  alarm_name          = "${var.entorno}-validacion-dlq-con-mensajes"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.dlq.name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
}

# --- Permisos mínimos por servicio ---
data "aws_iam_policy_document" "solicitudes" {
  statement {
    sid       = "FirmarSubidas"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cuarentena.arn}/entrada/*"]
  }
  statement {
    sid       = "FirmarDescargas"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.validadas.arn}/archivos/*"]
  }
  statement {
    sid       = "EstadoDeCargas"
    actions   = ["dynamodb:PutItem", "dynamodb:GetItem"]
    resources = [aws_dynamodb_table.cargas.arn]
  }
}

data "aws_iam_policy_document" "validador" {
  statement {
    sid       = "LeerCuarentena"
    actions   = ["s3:GetObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.cuarentena.arn}/entrada/*"]
  }
  statement {
    sid       = "PromoverAValidadas"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.validadas.arn}/archivos/*"]
  }
  statement {
    sid       = "Cola"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:ChangeMessageVisibility", "sqs:GetQueueAttributes"]
    resources = [aws_sqs_queue.validacion.arn]
  }
  statement {
    sid       = "Estado"
    actions   = ["dynamodb:GetItem", "dynamodb:UpdateItem", "dynamodb:Query"]
    resources = [aws_dynamodb_table.cargas.arn, "${aws_dynamodb_table.cargas.arn}/index/por-estado"]
  }
}

resource "aws_iam_policy" "solicitudes" {
  name   = "${var.entorno}-cargas-solicitudes"
  policy = data.aws_iam_policy_document.solicitudes.json
}

resource "aws_iam_policy" "validador" {
  name   = "${var.entorno}-cargas-validador"
  policy = data.aws_iam_policy_document.validador.json
}

output "bucket_cuarentena" {
  value = aws_s3_bucket.cuarentena.bucket
}

output "bucket_validadas" {
  value = aws_s3_bucket.validadas.bucket
}

output "cola_validacion" {
  value = aws_sqs_queue.validacion.url
}
