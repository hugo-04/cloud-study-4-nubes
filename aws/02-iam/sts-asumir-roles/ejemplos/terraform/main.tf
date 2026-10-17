terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Dos proveedores: cuenta A (origen) y cuenta B (destino). En la práctica cada uno lleva su
# bloque assume_role / perfil hacia su cuenta; aquí se omite para que el ejemplo sea corto.
provider "aws" {
  alias  = "origen"
  region = var.region
}

provider "aws" {
  alias  = "destino"
  region = var.region
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "cuenta_origen_id" {
  type = string
}

variable "cuenta_destino_id" {
  type = string
}

variable "external_id" {
  description = "Secreto único para este vínculo (generado por quien opera el servicio, no por el cliente)."
  type        = string
  sensitive   = true
}

variable "bucket_logs" {
  type = string
}

# ---------- Cuenta B: rol de lectura de logs con confianza acotada ----------
data "aws_iam_policy_document" "confianza_b" {
  provider = aws.destino

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.cuenta_origen_id}:role/pedidos-app-tarea"]
    }

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.external_id]
    }
  }
}

data "aws_iam_policy_document" "lectura_logs" {
  provider = aws.destino

  statement {
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.bucket_logs}", "arn:aws:s3:::${var.bucket_logs}/*"]
  }
}

resource "aws_iam_role" "lector_logs" {
  provider = aws.destino

  name                 = "lector-logs"
  assume_role_policy   = data.aws_iam_policy_document.confianza_b.json
  max_session_duration = 3600
  tags                 = { proposito = "lectura-logs-entre-cuentas" }
}

resource "aws_iam_role_policy" "lector_logs" {
  provider = aws.destino

  name   = "leer-logs"
  role   = aws_iam_role.lector_logs.id
  policy = data.aws_iam_policy_document.lectura_logs.json
}

# ---------- Cuenta A: permiso para asumir SOLO ese rol ----------
data "aws_iam_policy_document" "asumir_en_origen" {
  provider = aws.origen

  statement {
    actions   = ["sts:AssumeRole"]
    resources = [aws_iam_role.lector_logs.arn]
  }
}

resource "aws_iam_role_policy" "asumir" {
  provider = aws.origen

  name   = "asumir-lector-logs"
  role   = "pedidos-app-tarea"
  policy = data.aws_iam_policy_document.asumir_en_origen.json
}

output "rol_destino_arn" {
  value = aws_iam_role.lector_logs.arn
}
