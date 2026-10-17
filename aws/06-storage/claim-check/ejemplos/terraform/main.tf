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

locals {
  retencion_dlq_dias = 14
  retencion_objeto   = 30 # mayor que la retención de la DLQ
}

# --- Almacén versionado y privado ---
resource "aws_s3_bucket" "cc" {
  bucket = "modalima-${var.entorno}-claimcheck-${data.aws_caller_identity.actual.account_id}-${var.region}"
}

resource "aws_s3_bucket_public_access_block" "cc" {
  bucket                  = aws_s3_bucket.cc.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "cc" {
  bucket = aws_s3_bucket.cc.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cc" {
  bucket     = aws_s3_bucket.cc.id
  depends_on = [aws_s3_bucket_versioning.cc]

  rule {
    id     = "huerfanos-y-viejos"
    status = "Enabled"
    filter {
      prefix = "cc/"
    }
    expiration {
      days = local.retencion_objeto
    }
    noncurrent_version_expiration {
      noncurrent_days = 1
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

# --- Cola, DLQ y cifrado ---
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.entorno}-claimcheck-dlq"
  message_retention_seconds = local.retencion_dlq_dias * 86400
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "cola" {
  name                       = "${var.entorno}-claimcheck"
  visibility_timeout_seconds = 300 # mayor que el tiempo máximo de procesamiento
  receive_wait_time_seconds  = 20  # long polling
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 5
  })
}

resource "aws_cloudwatch_metric_alarm" "dlq_con_mensajes" {
  alarm_name          = "${var.entorno}-claimcheck-dlq-con-mensajes"
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

# --- Permisos mínimos ---
data "aws_iam_policy_document" "productor" {
  statement {
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cc.arn}/cc/pedidos/*"]
  }
  statement {
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.cola.arn]
  }
}

data "aws_iam_policy_document" "consumidor" {
  statement {
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = ["${aws_s3_bucket.cc.arn}/cc/pedidos/*"]
  }
  statement {
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:ChangeMessageVisibility", "sqs:GetQueueAttributes"]
    resources = [aws_sqs_queue.cola.arn]
  }
}

resource "aws_iam_policy" "productor" {
  name   = "${var.entorno}-claimcheck-productor"
  policy = data.aws_iam_policy_document.productor.json
}

resource "aws_iam_policy" "consumidor" {
  name   = "${var.entorno}-claimcheck-consumidor"
  policy = data.aws_iam_policy_document.consumidor.json
}

output "cola_url" {
  value = aws_sqs_queue.cola.url
}

output "bucket" {
  value = aws_s3_bucket.cc.id
}
