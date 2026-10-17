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

variable "origenes_permitidos" {
  type        = list(string)
  description = "Orígenes del navegador que pueden subir directo, p. ej. https://app.modalima.com"
}

data "aws_caller_identity" "actual" {}

resource "aws_s3_bucket" "subidas" {
  bucket = "modalima-${var.entorno}-subidas-${data.aws_caller_identity.actual.account_id}-${var.region}"
}

resource "aws_s3_bucket_public_access_block" "subidas" {
  bucket                  = aws_s3_bucket.subidas.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CORS: origen, métodos y cabeceras exactos (no usar "*" en producción)
resource "aws_s3_bucket_cors_configuration" "subidas" {
  bucket = aws_s3_bucket.subidas.id

  cors_rule {
    allowed_origins = var.origenes_permitidos
    allowed_methods = ["PUT", "POST", "GET", "HEAD"]
    allowed_headers = ["Content-Type", "x-amz-checksum-sha256", "x-amz-meta-*"]
    expose_headers  = ["ETag", "x-amz-version-id"]
    max_age_seconds = 600
  }
}

# Lo subido sin confirmar se borra solo
resource "aws_s3_bucket_lifecycle_configuration" "subidas" {
  bucket = aws_s3_bucket.subidas.id

  rule {
    id     = "temporales"
    status = "Enabled"
    filter {
      prefix = "uploads/"
    }
    expiration {
      days = 2
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

# Permiso mínimo del rol que FIRMA las URLs: solo el prefijo uploads/
data "aws_iam_policy_document" "firmante" {
  statement {
    actions   = ["s3:PutObject", "s3:GetObject"]
    resources = ["${aws_s3_bucket.subidas.arn}/uploads/*"]
  }
}

resource "aws_iam_policy" "firmante" {
  name   = "${var.entorno}-subidas-firmante"
  policy = data.aws_iam_policy_document.firmante.json
}

output "bucket" {
  value = aws_s3_bucket.subidas.id
}

output "politica_firmante_arn" {
  value = aws_iam_policy.firmante.arn
}
