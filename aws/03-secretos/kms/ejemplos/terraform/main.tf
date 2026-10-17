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

variable "rol_administrador_arn" {
  type = string
}

variable "rol_aplicacion_arn" {
  type = string
}

variable "multi_region" {
  description = "true para claves multi-región (recuperación ante desastres)."
  type        = bool
  default     = false
}

data "aws_caller_identity" "actual" {}

data "aws_iam_policy_document" "clave" {
  # 1) La cuenta habilita IAM (sin esto, ni IAM sirve)
  statement {
    sid       = "HabilitarIamEnLaCuenta"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.actual.account_id}:root"]
    }
  }

  # 2) Administradores: gestionan, NO usan
  statement {
    sid = "AdministradoresSinUso"
    actions = [
      "kms:Create*", "kms:Describe*", "kms:Enable*", "kms:List*", "kms:Put*", "kms:Update*",
      "kms:Revoke*", "kms:Disable*", "kms:Get*", "kms:TagResource", "kms:UntagResource",
      "kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion",
    ]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [var.rol_administrador_arn]
    }
  }

  # 3) Usuarios: usan, NO administran, y solo con el contexto esperado
  statement {
    sid       = "UsoDeLaAplicacion"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [var.rol_aplicacion_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:EncryptionContext:servicio"
      values   = ["pedidos"]
    }
  }
}

resource "aws_kms_key" "pedidos" {
  description              = "Datos de pedidos (${var.entorno})"
  key_usage                = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  enable_key_rotation      = true
  rotation_period_in_days  = 365
  deletion_window_in_days  = 30
  multi_region             = var.multi_region
  policy                   = data.aws_iam_policy_document.clave.json

  tags = { servicio = "pedidos", entorno = var.entorno }
}

resource "aws_kms_alias" "pedidos" {
  name          = "alias/${var.entorno}-pedidos-datos"
  target_key_id = aws_kms_key.pedidos.key_id
}

# Clave asimétrica de firma (por ejemplo, firmar documentos o tokens propios)
resource "aws_kms_key" "firma" {
  description              = "Firma de documentos (${var.entorno})"
  key_usage                = "SIGN_VERIFY"
  customer_master_key_spec = "ECC_NIST_P256"
  deletion_window_in_days  = 30
  tags                     = { servicio = "facturas", entorno = var.entorno }
}

resource "aws_kms_alias" "firma" {
  name          = "alias/${var.entorno}-facturas-firma"
  target_key_id = aws_kms_key.firma.key_id
}

# Concesión temporal para un rol (ejemplo): solo descifrar
resource "aws_kms_grant" "lectura_reportes" {
  name              = "reportes-descifrar"
  key_id            = aws_kms_key.pedidos.key_id
  grantee_principal = var.rol_aplicacion_arn
  operations        = ["Decrypt"]

  constraints {
    encryption_context_equals = {
      servicio = "pedidos"
    }
  }
}

output "alias_datos" {
  value = aws_kms_alias.pedidos.name
}

output "clave_datos_arn" {
  value = aws_kms_key.pedidos.arn
}
