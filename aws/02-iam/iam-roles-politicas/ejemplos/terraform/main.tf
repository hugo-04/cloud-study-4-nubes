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

data "aws_caller_identity" "actual" {}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "cola_pedidos_arn" {
  type = string
}

variable "bucket_datos" {
  type = string
}

variable "vpce_s3_id" {
  type = string
}

variable "clave_kms_arn" {
  type = string
}

# ---------- Política de confianza: solo tareas de ECS de ESTA cuenta ----------
data "aws_iam_policy_document" "confianza_ecs" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.actual.account_id]
    }
  }
}

# ---------- Permisos mínimos ----------
data "aws_iam_policy_document" "app" {
  statement {
    sid       = "LeerCola"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
    resources = [var.cola_pedidos_arn]
  }

  statement {
    sid       = "EscribirFacturas"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${var.bucket_datos}/facturas/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceVpce"
      values   = [var.vpce_s3_id]
    }
  }

  statement {
    sid       = "ClaveDeFacturas"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [var.clave_kms_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${var.region}.amazonaws.com"]
    }
  }
}

# ---------- Límite de permisos para roles creados por equipos ----------
data "aws_iam_policy_document" "limite" {
  statement {
    sid       = "TopeDeServicios"
    actions   = ["s3:*", "sqs:*", "sns:*", "dynamodb:*", "logs:*", "kms:Decrypt", "kms:GenerateDataKey", "secretsmanager:GetSecretValue"]
    resources = ["*"]
  }

  statement {
    sid       = "NuncaIamNiOrganizacion"
    effect    = "Deny"
    actions   = ["iam:*", "organizations:*", "account:*"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "limite_equipos" {
  name   = "limite-permisos-equipos"
  policy = data.aws_iam_policy_document.limite.json
}

resource "aws_iam_policy" "app" {
  name        = "pedidos-app"
  description = "Permisos minimos de la app de pedidos"
  policy      = data.aws_iam_policy_document.app.json
}

resource "aws_iam_role" "app" {
  name                 = "pedidos-app-tarea"
  assume_role_policy   = data.aws_iam_policy_document.confianza_ecs.json
  permissions_boundary = aws_iam_policy.limite_equipos.arn
  max_session_duration = 3600

  tags = { proyecto = "tienda", rol = "tarea-ecs" }
}

resource "aws_iam_role_policy_attachment" "app" {
  role       = aws_iam_role.app.name
  policy_arn = aws_iam_policy.app.arn
}

# ---------- Contraseñas (si quedan usuarios IAM) y Access Analyzer ----------
resource "aws_iam_account_password_policy" "fuerte" {
  minimum_password_length      = 14
  require_lowercase_characters = true
  require_uppercase_characters = true
  require_numbers              = true
  require_symbols              = true
  max_password_age             = 90
  password_reuse_prevention    = 12
}

resource "aws_accessanalyzer_analyzer" "cuenta" {
  analyzer_name = "analizador-cuenta"
  type          = "ACCOUNT"
}

output "rol_app_arn" {
  value = aws_iam_role.app.arn
}
