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

variable "modo_stream" {
  type        = string
  default     = "ON_DEMAND"
  description = "ON_DEMAND (carga irregular) o PROVISIONED (carga estable y medida)"
  validation {
    condition     = contains(["ON_DEMAND", "PROVISIONED"], var.modo_stream)
    error_message = "modo_stream debe ser ON_DEMAND o PROVISIONED."
  }
}

variable "shards" {
  type        = number
  default     = 2
  description = "Solo si modo_stream = PROVISIONED (usar el dimensionador de uso-en-java.md)"
}

variable "retencion_horas" {
  type    = number
  default = 48
}

data "aws_caller_identity" "actual" {}

# --- El stream (cifrado, con retención suficiente para reprocesar) ---
resource "aws_kinesis_stream" "clics" {
  name             = "${var.entorno}-clics"
  retention_period = var.retencion_horas
  encryption_type  = "KMS"
  kms_key_id       = "alias/aws/kinesis"

  shard_count = var.modo_stream == "PROVISIONED" ? var.shards : null

  stream_mode_details {
    stream_mode = var.modo_stream
  }

  shard_level_metrics = ["IncomingBytes", "IncomingRecords", "IteratorAgeMilliseconds", "WriteProvisionedThroughputExceeded"]
}

# --- Lago de datos: Firehose entrega lo crudo a S3 (gzip, particionado por fecha) ---
resource "aws_s3_bucket" "lago" {
  bucket = "modalima-lago-${var.entorno}-${data.aws_caller_identity.actual.account_id}"
}

resource "aws_s3_bucket_public_access_block" "lago" {
  bucket                  = aws_s3_bucket.lago.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lago" {
  bucket = aws_s3_bucket.lago.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "lago" {
  bucket = aws_s3_bucket.lago.id
  rule {
    id     = "enfriar-y-vencer"
    status = "Enabled"
    filter {
      prefix = "clics/"
    }
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    expiration {
      days = 400
    }
  }
}

data "aws_iam_policy_document" "firehose_confianza" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [data.aws_caller_identity.actual.account_id]
    }
  }
}

resource "aws_iam_role" "firehose" {
  name               = "${var.entorno}-firehose-clics"
  assume_role_policy = data.aws_iam_policy_document.firehose_confianza.json
}

data "aws_iam_policy_document" "firehose_permisos" {
  statement {
    actions   = ["kinesis:DescribeStream", "kinesis:GetShardIterator", "kinesis:GetRecords", "kinesis:ListShards"]
    resources = [aws_kinesis_stream.clics.arn]
  }
  statement {
    actions   = ["s3:AbortMultipartUpload", "s3:GetBucketLocation", "s3:GetObject", "s3:ListBucket", "s3:ListBucketMultipartUploads", "s3:PutObject"]
    resources = [aws_s3_bucket.lago.arn, "${aws_s3_bucket.lago.arn}/*"]
  }
}

resource "aws_iam_role_policy" "firehose" {
  role   = aws_iam_role.firehose.id
  policy = data.aws_iam_policy_document.firehose_permisos.json
}

resource "aws_kinesis_firehose_delivery_stream" "al_lago" {
  name        = "${var.entorno}-clics-al-lago"
  destination = "extended_s3"

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.clics.arn
    role_arn           = aws_iam_role.firehose.arn
  }

  extended_s3_configuration {
    role_arn            = aws_iam_role.firehose.arn
    bucket_arn          = aws_s3_bucket.lago.arn
    prefix              = "clics/anio=!{timestamp:yyyy}/mes=!{timestamp:MM}/dia=!{timestamp:dd}/"
    error_output_prefix = "errores/!{firehose:error-output-type}/anio=!{timestamp:yyyy}/mes=!{timestamp:MM}/dia=!{timestamp:dd}/"
    buffering_size      = 64
    buffering_interval  = 60
    compression_format  = "GZIP"
  }
}

# --- Métricas por ventana y checkpoints del consumidor ---
resource "aws_dynamodb_table" "metricas" {
  name         = "${var.entorno}-metricas-clics"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pagina"
  range_key    = "ventana"

  attribute {
    name = "pagina"
    type = "S"
  }
  attribute {
    name = "ventana"
    type = "S"
  }

  ttl {
    attribute_name = "expira"
    enabled        = true
  }
}

resource "aws_dynamodb_table" "checkpoints" {
  name         = "${var.entorno}-checkpoints-clics"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "shard"

  attribute {
    name = "shard"
    type = "S"
  }
}

# --- Alarmas sobre lo que importa en un stream ---
resource "aws_cloudwatch_metric_alarm" "atraso" {
  alarm_name          = "${var.entorno}-clics-consumidor-atrasado"
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

resource "aws_cloudwatch_metric_alarm" "estrangulado" {
  alarm_name          = "${var.entorno}-clics-escritura-estrangulada"
  namespace           = "AWS/Kinesis"
  metric_name         = "WriteProvisionedThroughputExceeded"
  dimensions          = { StreamName = aws_kinesis_stream.clics.name }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
}

# --- Permisos mínimos ---
data "aws_iam_policy_document" "productor" {
  statement {
    actions   = ["kinesis:PutRecords", "kinesis:PutRecord"]
    resources = [aws_kinesis_stream.clics.arn]
  }
}

data "aws_iam_policy_document" "consumidor" {
  statement {
    actions   = ["kinesis:ListShards", "kinesis:GetShardIterator", "kinesis:GetRecords", "kinesis:DescribeStreamSummary"]
    resources = [aws_kinesis_stream.clics.arn]
  }
  statement {
    actions   = ["dynamodb:PutItem", "dynamodb:GetItem"]
    resources = [aws_dynamodb_table.metricas.arn, aws_dynamodb_table.checkpoints.arn]
  }
}

resource "aws_iam_policy" "productor" {
  name   = "${var.entorno}-clics-productor"
  policy = data.aws_iam_policy_document.productor.json
}

resource "aws_iam_policy" "consumidor" {
  name   = "${var.entorno}-clics-consumidor"
  policy = data.aws_iam_policy_document.consumidor.json
}

output "stream" {
  value = aws_kinesis_stream.clics.name
}

output "lago" {
  value = aws_s3_bucket.lago.bucket
}
