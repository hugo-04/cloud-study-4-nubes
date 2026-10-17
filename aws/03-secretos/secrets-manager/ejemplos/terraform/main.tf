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

variable "clave_kms_arn" {
  description = "CMK que cifra el secreto (necesaria para acceso entre cuentas)."
  type        = string
}

variable "rol_lectura_arn" {
  description = "Rol de la aplicación que lee el secreto."
  type        = string
}

variable "lambda_rotacion_arn" {
  description = "Lambda de rotación (plantilla del repositorio sin servidor de AWS para el motor elegido). Vacío = sin rotación."
  type        = string
  default     = ""
}

variable "replica_region" {
  description = "Región de réplica (vacío = sin réplica)."
  type        = string
  default     = ""
}

data "aws_caller_identity" "actual" {}

data "aws_organizations_organization" "org" {}

# El CONTENEDOR se crea por código; el VALOR no pasa por Terraform ni por su estado.
resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.entorno}/pedidos/db"
  description             = "Credenciales de la base de pedidos (${var.entorno})"
  kms_key_id              = var.clave_kms_arn
  recovery_window_in_days = 30

  dynamic "replica" {
    for_each = var.replica_region == "" ? [] : [var.replica_region]
    content {
      region = replica.value
    }
  }

  tags = { servicio = "pedidos", entorno = var.entorno, rotacion = "automatica" }
}

data "aws_iam_policy_document" "recurso" {
  statement {
    sid       = "LecturaSoloDeLaApp"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [var.rol_lectura_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [data.aws_organizations_organization.org.id]
    }
  }
}

resource "aws_secretsmanager_secret_policy" "db" {
  secret_arn = aws_secretsmanager_secret.db.arn
  policy     = data.aws_iam_policy_document.recurso.json
}

# Rotación: cada 30 días, ventana de 2 horas
resource "aws_secretsmanager_secret_rotation" "db" {
  count = var.lambda_rotacion_arn == "" ? 0 : 1

  secret_id           = aws_secretsmanager_secret.db.id
  rotation_lambda_arn = var.lambda_rotacion_arn

  rotation_rules {
    schedule_expression = "rate(30 days)"
    duration            = "2h"
  }
}

# Política de identidad para la aplicación (para adjuntar a su rol)
data "aws_iam_policy_document" "lectura" {
  statement {
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [aws_secretsmanager_secret.db.arn]
  }

  statement {
    actions   = ["kms:Decrypt"]
    resources = [var.clave_kms_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${var.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "lectura" {
  name   = "${var.entorno}-pedidos-lee-secreto-db"
  policy = data.aws_iam_policy_document.lectura.json
}

output "secreto_arn" {
  value = aws_secretsmanager_secret.db.arn
}

output "politica_lectura_arn" {
  value = aws_iam_policy.lectura.arn
}
