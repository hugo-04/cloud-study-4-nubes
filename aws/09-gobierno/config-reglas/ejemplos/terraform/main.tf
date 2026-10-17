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

variable "arn_lambda_regla_etiquetas" {
  type        = string
  description = "ARN de la Lambda de la regla personalizada de etiquetas"
}

variable "arn_topico_alertas" {
  type        = string
  description = "Tópico SNS que recibe los cambios de cumplimiento"
}

data "aws_caller_identity" "actual" {}

resource "aws_kms_key" "config" {
  description         = "Cifrado del historial de Config ${var.entorno}"
  enable_key_rotation = true
}

# --- Bucket de evidencia: privado, cifrado, versionado ---
resource "aws_s3_bucket" "config" {
  bucket = "${var.entorno}-config-${data.aws_caller_identity.actual.account_id}"
}

resource "aws_s3_bucket_public_access_block" "config" {
  bucket                  = aws_s3_bucket.config.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
  bucket = aws_s3_bucket.config.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.config.arn
    }
  }
}

resource "aws_s3_bucket_versioning" "config" {
  bucket = aws_s3_bucket.config.id
  versioning_configuration {
    status = "Enabled"
  }
}

data "aws_iam_policy_document" "bucket_config" {
  statement {
    sid       = "AclYListado"
    actions   = ["s3:GetBucketAcl", "s3:ListBucket"]
    resources = [aws_s3_bucket.config.arn]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = [data.aws_caller_identity.actual.account_id]
    }
  }
  statement {
    sid       = "Entrega"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.config.arn}/AWSLogs/${data.aws_caller_identity.actual.account_id}/Config/*"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = [data.aws_caller_identity.actual.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "config" {
  bucket = aws_s3_bucket.config.id
  policy = data.aws_iam_policy_document.bucket_config.json
}

# --- Rol del registrador ---
data "aws_iam_policy_document" "confianza_config" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "config" {
  name               = "${var.entorno}-config-registrador"
  assume_role_policy = data.aws_iam_policy_document.confianza_config.json
}

resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

# --- Registrador y canal ---
resource "aws_config_configuration_recorder" "este" {
  name     = "default"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }

  recording_mode {
    recording_frequency = "CONTINUOUS"
  }
}

resource "aws_config_delivery_channel" "este" {
  name           = "default"
  s3_bucket_name = aws_s3_bucket.config.bucket

  snapshot_delivery_properties {
    delivery_frequency = "TwentyFour_Hours"
  }

  depends_on = [aws_config_configuration_recorder.este, aws_s3_bucket_policy.config]
}

resource "aws_config_configuration_recorder_status" "este" {
  name       = aws_config_configuration_recorder.este.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.este]
}

# --- Reglas administradas ---
resource "aws_config_config_rule" "s3_sin_lectura_publica" {
  name = "s3-lectura-publica-prohibida"
  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }
  depends_on = [aws_config_configuration_recorder.este]
}

resource "aws_config_config_rule" "volumenes_cifrados" {
  name = "volumenes-cifrados"
  source {
    owner             = "AWS"
    source_identifier = "ENCRYPTED_VOLUMES"
  }
  depends_on = [aws_config_configuration_recorder.este]
}

resource "aws_config_config_rule" "rds_cifrado" {
  name = "rds-cifrado-en-reposo"
  source {
    owner             = "AWS"
    source_identifier = "RDS_STORAGE_ENCRYPTED"
  }
  depends_on = [aws_config_configuration_recorder.este]
}

resource "aws_config_config_rule" "raiz_sin_claves" {
  name = "raiz-sin-claves-de-acceso"
  source {
    owner             = "AWS"
    source_identifier = "IAM_ROOT_ACCESS_KEY_CHECK"
  }
  maximum_execution_frequency = "TwentyFour_Hours"
  depends_on                  = [aws_config_configuration_recorder.este]
}

resource "aws_config_config_rule" "etiquetas_administrada" {
  name = "etiquetas-administrada"
  source {
    owner             = "AWS"
    source_identifier = "REQUIRED_TAGS"
  }
  scope {
    compliance_resource_types = ["AWS::EC2::Instance", "AWS::RDS::DBInstance", "AWS::S3::Bucket"]
  }
  input_parameters = jsonencode({
    tag1Key = "centro-costo"
    tag2Key = "entorno"
  })
  depends_on = [aws_config_configuration_recorder.este]
}

# --- Regla personalizada (Lambda): valores permitidos de etiquetas ---
resource "aws_lambda_permission" "config_invoca" {
  statement_id   = "AllowConfigInvoke"
  action         = "lambda:InvokeFunction"
  function_name  = var.arn_lambda_regla_etiquetas
  principal      = "config.amazonaws.com"
  source_account = data.aws_caller_identity.actual.account_id
}

resource "aws_config_config_rule" "etiquetas_personalizada" {
  name = "etiquetas-obligatorias"
  source {
    owner             = "CUSTOM_LAMBDA"
    source_identifier = var.arn_lambda_regla_etiquetas
    source_detail {
      message_type = "ConfigurationItemChangeNotification"
    }
    source_detail {
      message_type = "OversizedConfigurationItemChangeNotification"
    }
  }
  input_parameters = file("${path.module}/../json/regla-etiquetas-parametros.json")
  depends_on       = [aws_config_configuration_recorder.este, aws_lambda_permission.config_invoca]
}

# --- Remediación MANUAL: bloquear el acceso público de un bucket (documento de SSM Automation) ---
resource "aws_config_remediation_configuration" "s3_acceso_publico" {
  config_rule_name = aws_config_config_rule.s3_sin_lectura_publica.name
  target_type      = "SSM_DOCUMENT"
  target_id        = "AWS-DisableS3BucketPublicReadWrite"
  automatic        = false

  parameter {
    name           = "S3BucketName"
    resource_value = "RESOURCE_ID"
  }
  parameter {
    name         = "AutomationAssumeRole"
    static_value = aws_iam_role.config.arn
  }
}

# --- Agregador de la cuenta (para varias regiones) ---
resource "aws_config_configuration_aggregator" "cuenta" {
  name = "${var.entorno}-agregador"
  account_aggregation_source {
    account_ids = [data.aws_caller_identity.actual.account_id]
    all_regions = true
  }
}

# --- Cambios de cumplimiento a SNS (vía EventBridge) ---
resource "aws_cloudwatch_event_rule" "incumplimiento" {
  name = "${var.entorno}-config-incumple"
  event_pattern = jsonencode({
    source        = ["aws.config"]
    "detail-type" = ["Config Rules Compliance Change"]
    detail        = { newEvaluationResult = { complianceType = ["NON_COMPLIANT"] } }
  })
}

resource "aws_cloudwatch_event_target" "incumplimiento_sns" {
  rule = aws_cloudwatch_event_rule.incumplimiento.name
  arn  = var.arn_topico_alertas
}

output "bucket_evidencia" {
  value = aws_s3_bucket.config.bucket
}
