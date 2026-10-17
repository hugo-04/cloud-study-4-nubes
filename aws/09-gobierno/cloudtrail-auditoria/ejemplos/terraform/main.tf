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

variable "arn_topico_seguridad" {
  type        = string
  description = "Tópico SNS que recibe las alarmas de seguridad"
}

data "aws_caller_identity" "actual" {}
data "aws_partition" "actual" {}

locals {
  nombre_traza = "${var.entorno}-traza-principal"
  arn_traza    = "arn:${data.aws_partition.actual.partition}:cloudtrail:${var.region}:${data.aws_caller_identity.actual.account_id}:trail/${local.nombre_traza}"
}

# --- Clave KMS (la política permite a CloudTrail cifrar, acotada a ESTA traza) ---
data "aws_iam_policy_document" "clave" {
  statement {
    sid       = "Administracion"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.actual.account_id}:root"]
    }
  }
  statement {
    sid       = "CloudTrailCifra"
    actions   = ["kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.arn_traza]
    }
  }
}

resource "aws_kms_key" "traza" {
  description         = "Cifrado de CloudTrail ${var.entorno}"
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.clave.json
}

# --- Bucket de evidencia ---
resource "aws_s3_bucket" "auditoria" {
  bucket = "${var.entorno}-auditoria-${data.aws_caller_identity.actual.account_id}"
}

resource "aws_s3_bucket_public_access_block" "auditoria" {
  bucket                  = aws_s3_bucket.auditoria.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "auditoria" {
  bucket = aws_s3_bucket.auditoria.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "auditoria" {
  bucket = aws_s3_bucket.auditoria.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.traza.arn
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "auditoria" {
  bucket = aws_s3_bucket.auditoria.id
  rule {
    id     = "archivar-y-expirar"
    status = "Enabled"
    filter {}
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
    expiration {
      days = 2555
    }
  }
}

data "aws_iam_policy_document" "bucket" {
  statement {
    sid       = "AclCloudTrail"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.auditoria.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.arn_traza]
    }
  }
  statement {
    sid       = "EscrituraCloudTrail"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.auditoria.arn}/AWSLogs/${data.aws_caller_identity.actual.account_id}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.arn_traza]
    }
  }
  statement {
    sid       = "SoloTransporteSeguro"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.auditoria.arn, "${aws_s3_bucket.auditoria.arn}/*"]
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

resource "aws_s3_bucket_policy" "auditoria" {
  bucket = aws_s3_bucket.auditoria.id
  policy = data.aws_iam_policy_document.bucket.json
}

# --- CloudWatch Logs para detección en tiempo casi real ---
resource "aws_cloudwatch_log_group" "traza" {
  name              = "/auditoria/${var.entorno}/cloudtrail"
  retention_in_days = 90
}

data "aws_iam_policy_document" "confianza_logs" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "permiso_logs" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.traza.arn}:*"]
  }
}

resource "aws_iam_role" "traza_logs" {
  name               = "${var.entorno}-cloudtrail-a-logs"
  assume_role_policy = data.aws_iam_policy_document.confianza_logs.json
}

resource "aws_iam_role_policy" "traza_logs" {
  name   = "escribir-logs"
  role   = aws_iam_role.traza_logs.id
  policy = data.aws_iam_policy_document.permiso_logs.json
}

# --- La traza ---
resource "aws_cloudtrail" "principal" {
  name                          = local.nombre_traza
  s3_bucket_name                = aws_s3_bucket.auditoria.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  kms_key_id                    = aws_kms_key.traza.arn
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.traza.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.traza_logs.arn

  # Eventos de datos SOLO donde aportan: escrituras en el bucket de documentos sensibles
  advanced_event_selector {
    name = "Escrituras en el bucket de documentos"
    field_selector {
      field  = "eventCategory"
      equals = ["Data"]
    }
    field_selector {
      field  = "resources.type"
      equals = ["AWS::S3::Object"]
    }
    field_selector {
      field  = "readOnly"
      equals = ["false"]
    }
    field_selector {
      field       = "resources.ARN"
      starts_with = ["arn:aws:s3:::${var.entorno}-documentos-sensibles/"]
    }
  }

  advanced_event_selector {
    name = "Eventos de administracion"
    field_selector {
      field  = "eventCategory"
      equals = ["Management"]
    }
  }

  insight_selector {
    insight_type = "ApiCallRateInsight"
  }

  depends_on = [aws_s3_bucket_policy.auditoria]
}

# --- Alarmas de seguridad (patrones clásicos de CIS) ---
locals {
  detecciones = {
    uso-raiz = {
      patron = "{ $.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\" }"
    }
    consola-sin-mfa = {
      patron = "{ ($.eventName = \"ConsoleLogin\") && ($.additionalEventData.MFAUsed != \"Yes\") && ($.userIdentity.type = \"IAMUser\") && ($.responseElements.ConsoleLogin = \"Success\") }"
    }
    acceso-denegado = {
      patron = "{ ($.errorCode = \"*UnauthorizedOperation\") || ($.errorCode = \"AccessDenied*\") }"
    }
    cambios-traza = {
      patron = "{ ($.eventName = StopLogging) || ($.eventName = DeleteTrail) || ($.eventName = UpdateTrail) || ($.eventName = PutEventSelectors) }"
    }
    cambios-politicas-iam = {
      patron = "{ ($.eventName = DeleteGroupPolicy) || ($.eventName = DeleteRolePolicy) || ($.eventName = DeleteUserPolicy) || ($.eventName = PutGroupPolicy) || ($.eventName = PutRolePolicy) || ($.eventName = PutUserPolicy) || ($.eventName = CreatePolicy) || ($.eventName = AttachRolePolicy) || ($.eventName = AttachUserPolicy) }"
    }
  }
}

resource "aws_cloudwatch_log_metric_filter" "deteccion" {
  for_each       = local.detecciones
  name           = "${var.entorno}-${each.key}"
  log_group_name = aws_cloudwatch_log_group.traza.name
  pattern        = each.value.patron

  metric_transformation {
    name      = each.key
    namespace = "Auditoria/${var.entorno}"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "deteccion" {
  for_each            = local.detecciones
  alarm_name          = "${var.entorno}-auditoria-${each.key}"
  namespace           = "Auditoria/${var.entorno}"
  metric_name         = each.key
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = each.key == "acceso-denegado" ? 20 : 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.arn_topico_seguridad]

  depends_on = [aws_cloudwatch_log_metric_filter.deteccion]
}

# --- CloudTrail Lake: eventos de administración consultables con SQL ---
resource "aws_cloudtrail_event_data_store" "lake" {
  name                           = "${var.entorno}-eventos"
  retention_period               = 365
  multi_region_enabled           = true
  organization_enabled           = false
  termination_protection_enabled = true

  advanced_event_selector {
    name = "Administracion"
    field_selector {
      field  = "eventCategory"
      equals = ["Management"]
    }
  }
}

output "bucket_auditoria" {
  value = aws_s3_bucket.auditoria.bucket
}

output "arn_traza" {
  value = aws_cloudtrail.principal.arn
}
