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

variable "dominio" {
  type    = string
  default = "facturas"
}

data "aws_caller_identity" "actual" {}

locals {
  nombre = "modalima-${var.entorno}-${var.dominio}-${data.aws_caller_identity.actual.account_id}-${var.region}"
}

resource "aws_kms_key" "bucket" {
  description             = "Clave del bucket ${local.nombre}"
  enable_key_rotation     = true
  deletion_window_in_days = 14
}

resource "aws_kms_alias" "bucket" {
  name          = "alias/${var.entorno}-${var.dominio}-s3"
  target_key_id = aws_kms_key.bucket.key_id
}

resource "aws_s3_bucket" "datos" {
  bucket = local.nombre
}

resource "aws_s3_bucket_public_access_block" "datos" {
  bucket                  = aws_s3_bucket.datos.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "datos" {
  bucket = aws_s3_bucket.datos.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "datos" {
  bucket = aws_s3_bucket.datos.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "datos" {
  bucket = aws_s3_bucket.datos.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.bucket.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "datos" {
  bucket     = aws_s3_bucket.datos.id
  depends_on = [aws_s3_bucket_versioning.datos]

  rule {
    id     = "limpieza"
    status = "Enabled"
    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    noncurrent_version_expiration {
      noncurrent_days = 60
    }
    expiration {
      expired_object_delete_marker = true
    }
  }
}

data "aws_iam_policy_document" "bucket" {
  statement {
    sid       = "SoloTLS"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.datos.arn, "${aws_s3_bucket.datos.arn}/*"]
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
    sid       = "TLSMinimo12"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.datos.arn, "${aws_s3_bucket.datos.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "NumericLessThan"
      variable = "s3:TlsVersion"
      values   = ["1.2"]
    }
  }
}

resource "aws_s3_bucket_policy" "datos" {
  bucket     = aws_s3_bucket.datos.id
  policy     = data.aws_iam_policy_document.bucket.json
  depends_on = [aws_s3_bucket_public_access_block.datos]
}

# Permiso mínimo para la aplicación: solo su prefijo y la clave KMS
data "aws_iam_policy_document" "app" {
  statement {
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.datos.arn}/facturas/*"]
  }
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.datos.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["facturas/*"]
    }
  }
  statement {
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [aws_kms_key.bucket.arn]
  }
}

resource "aws_iam_policy" "app" {
  name   = "${var.entorno}-${var.dominio}-s3-app"
  policy = data.aws_iam_policy_document.app.json
}

output "bucket" {
  value = aws_s3_bucket.datos.id
}

output "politica_app_arn" {
  value = aws_iam_policy.app.arn
}

output "kms_arn" {
  value = aws_kms_key.bucket.arn
}
