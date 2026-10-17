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

data "aws_caller_identity" "actual" {}

resource "aws_s3_bucket" "datos" {
  bucket = "modalima-${var.entorno}-datos-${data.aws_caller_identity.actual.account_id}-${var.region}"
}

resource "aws_s3_bucket_public_access_block" "datos" {
  bucket                  = aws_s3_bucket.datos.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- Cola de entrada (notificación clásica) + DLQ ---
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.entorno}-eventos-s3-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "entrada" {
  name                       = "${var.entorno}-eventos-s3-entrada"
  visibility_timeout_seconds = 120
  receive_wait_time_seconds  = 20
  sqs_managed_sse_enabled    = true
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 5
  })
}

# La cola debe autorizar a S3, y SOLO a este bucket de esta cuenta
data "aws_iam_policy_document" "cola_entrada" {
  statement {
    sid       = "PermitirS3DeEsteBucket"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.entrada.arn]
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.datos.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.actual.account_id]
    }
  }
}

resource "aws_sqs_queue_policy" "entrada" {
  queue_url = aws_sqs_queue.entrada.id
  policy    = data.aws_iam_policy_document.cola_entrada.json
}

# --- Cola de exportes (la alimenta EventBridge) ---
resource "aws_sqs_queue" "exportes" {
  name                      = "${var.entorno}-eventos-s3-exportes"
  receive_wait_time_seconds = 20
  sqs_managed_sse_enabled   = true
}

resource "aws_cloudwatch_event_rule" "exportes" {
  name = "${var.entorno}-s3-exportes"
  event_pattern = jsonencode({
    source        = ["aws.s3"]
    "detail-type" = ["Object Created"]
    detail = {
      bucket = { name = [aws_s3_bucket.datos.id] }
      object = {
        key  = [{ prefix = "exportes/" }]
        size = [{ numeric = [">", 0] }]
      }
      reason = ["PutObject", "CompleteMultipartUpload"]
    }
  })
}

resource "aws_cloudwatch_event_target" "exportes" {
  rule = aws_cloudwatch_event_rule.exportes.name
  arn  = aws_sqs_queue.exportes.arn
}

data "aws_iam_policy_document" "cola_exportes" {
  statement {
    sid       = "PermitirEventBridgeDeEstaRegla"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.exportes.arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.exportes.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "exportes" {
  queue_url = aws_sqs_queue.exportes.id
  policy    = data.aws_iam_policy_document.cola_exportes.json
}

# --- UNA sola configuración de notificaciones por bucket: SQS clásico + EventBridge ---
resource "aws_s3_bucket_notification" "datos" {
  bucket      = aws_s3_bucket.datos.id
  eventbridge = true

  queue {
    id            = "csv-de-entrada"
    queue_arn     = aws_sqs_queue.entrada.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "entrada/"
    filter_suffix = ".csv"
  }

  depends_on = [aws_sqs_queue_policy.entrada]
}

output "cola_entrada_url" {
  value = aws_sqs_queue.entrada.url
}

output "cola_exportes_url" {
  value = aws_sqs_queue.exportes.url
}
