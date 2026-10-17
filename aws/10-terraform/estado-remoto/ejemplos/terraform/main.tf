terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      gestionado_por = "terraform"
      componente     = "estado-remoto"
    }
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "nombre_bucket" {
  description = "Nombre global único del bucket del estado"
  type        = string
  default     = "modalima-tfstate-111122223333"
}

variable "arn_rol_administrador" {
  description = "Único rol que puede borrar versiones del estado"
  type        = string
  default     = "arn:aws:iam::111122223333:role/administrador-estado"
}

variable "entornos" {
  description = "Entornos con su propio prefijo y su propia política de acceso"
  type        = set(string)
  default     = ["dev", "prod"]
}

variable "dias_versiones_antiguas" {
  type    = number
  default = 90
}

data "aws_caller_identity" "actual" {}
data "aws_partition" "actual" {}

locals {
  cuenta    = data.aws_caller_identity.actual.account_id
  particion = data.aws_partition.actual.partition
}

# ------------------------------------------------------------------ Clave KMS del estado
resource "aws_kms_key" "estado" {
  description             = "Cifra los estados de Terraform"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_alias" "estado" {
  name          = "alias/terraform-estado"
  target_key_id = aws_kms_key.estado.key_id
}

# ------------------------------------------------------------------ Bucket del estado
resource "aws_s3_bucket" "estado" {
  bucket = var.nombre_bucket

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "estado" {
  bucket = aws_s3_bucket.estado.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "estado" {
  bucket                  = aws_s3_bucket.estado.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "estado" {
  bucket = aws_s3_bucket.estado.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "estado" {
  bucket = aws_s3_bucket.estado.id

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.estado.arn
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "estado" {
  bucket = aws_s3_bucket.estado.id

  rule {
    id     = "versiones-antiguas"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days           = var.dias_versiones_antiguas
      newer_noncurrent_versions = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.estado]
}

data "aws_iam_policy_document" "bucket" {
  statement {
    sid       = "SoloTLS"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.estado.arn, "${aws_s3_bucket.estado.arn}/*"]

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

  statement {
    sid       = "SoloElAdministradorBorraVersiones"
    effect    = "Deny"
    actions   = ["s3:DeleteObjectVersion"]
    resources = ["${aws_s3_bucket.estado.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "ArnNotEquals"
      variable = "aws:PrincipalArn"
      values   = [var.arn_rol_administrador]
    }
  }
}

resource "aws_s3_bucket_policy" "estado" {
  bucket = aws_s3_bucket.estado.id
  policy = data.aws_iam_policy_document.bucket.json

  depends_on = [aws_s3_bucket_public_access_block.estado]
}

# ------------------------------------------------------------------ Políticas por entorno (se adjuntan a los roles de los pipelines)
data "aws_iam_policy_document" "pipeline_apply" {
  for_each = var.entornos

  statement {
    sid       = "ListarSoloElPrefijo"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.estado.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["env/${each.key}/*"]
    }
  }

  statement {
    sid       = "EstadoYCandadoDelEntorno"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.estado.arn}/env/${each.key}/*"]
  }

  statement {
    sid       = "ClaveDelEstado"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [aws_kms_key.estado.arn]
  }
}

resource "aws_iam_policy" "pipeline_apply" {
  for_each = var.entornos

  name   = "terraform-estado-apply-${each.key}"
  policy = data.aws_iam_policy_document.pipeline_apply[each.key].json
}

# El plan de un pull request solo lee el estado y escribe el candado.
data "aws_iam_policy_document" "pipeline_plan" {
  for_each = var.entornos

  statement {
    sid       = "ListarSoloElPrefijo"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.estado.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["env/${each.key}/*"]
    }
  }

  statement {
    sid       = "LeerEstado"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.estado.arn}/env/${each.key}/*"]
  }

  statement {
    sid       = "EscribirSoloElCandado"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.estado.arn}/env/${each.key}/*.tflock"]
  }

  statement {
    sid       = "ClaveDelEstado"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [aws_kms_key.estado.arn]
  }
}

resource "aws_iam_policy" "pipeline_plan" {
  for_each = var.entornos

  name   = "terraform-estado-plan-${each.key}"
  policy = data.aws_iam_policy_document.pipeline_plan[each.key].json
}

output "bucket_estado" {
  value = aws_s3_bucket.estado.id
}

output "clave_kms" {
  value = aws_kms_key.estado.arn
}

output "politicas_apply" {
  value = { for k, p in aws_iam_policy.pipeline_apply : k => p.arn }
}

output "politicas_plan" {
  value = { for k, p in aws_iam_policy.pipeline_plan : k => p.arn }
}
