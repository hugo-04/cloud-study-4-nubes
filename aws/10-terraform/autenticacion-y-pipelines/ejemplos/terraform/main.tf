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
  region = "us-east-1"
}

variable "repositorio" {
  description = "Repositorio de GitHub que despliega (organización/nombre)"
  type        = string
  default     = "modalima/infra"
}

variable "entornos" {
  description = "Entornos de GitHub con rol propio"
  type        = set(string)
  default     = ["dev", "prod"]
}

variable "politicas_estado_plan" {
  description = "ARN de la política de estado (solo lectura + candado) por entorno; sale del módulo de estado remoto"
  type        = map(string)
  default = {
    dev  = "arn:aws:iam::111122223333:policy/terraform-estado-plan-dev"
    prod = "arn:aws:iam::111122223333:policy/terraform-estado-plan-prod"
  }
}

variable "politicas_estado_apply" {
  description = "ARN de la política de estado (lectura/escritura del prefijo) por entorno"
  type        = map(string)
  default = {
    dev  = "arn:aws:iam::111122223333:policy/terraform-estado-apply-dev"
    prod = "arn:aws:iam::111122223333:policy/terraform-estado-apply-prod"
  }
}

variable "servicios_permitidos" {
  description = "Servicios que este componente puede administrar (ajusta al componente)"
  type        = list(string)
  default     = ["sqs", "sns", "logs", "events", "ssm", "cloudwatch", "lambda", "dynamodb"]
}

data "aws_caller_identity" "actual" {}
data "aws_partition" "actual" {}

locals {
  particion = data.aws_partition.actual.partition
  cuenta    = data.aws_caller_identity.actual.account_id
  emisor    = "token.actions.githubusercontent.com"
}

# ------------------------------------------------------------------ Proveedor OIDC (uno por cuenta)
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://${local.emisor}"
  client_id_list = ["sts.amazonaws.com"]
}

# ------------------------------------------------------------------ Límite de permisos (techo de los roles que crea el pipeline)
data "aws_iam_policy_document" "limite" {
  statement {
    sid       = "ServiciosDeLaAplicacion"
    actions   = [for s in var.servicios_permitidos : "${s}:*"]
    resources = ["*"]
  }

  statement {
    sid    = "SinEscaladaDePrivilegios"
    effect = "Deny"
    actions = [
      "iam:CreateUser",
      "iam:CreateAccessKey",
      "iam:AttachUserPolicy",
      "iam:PutUserPolicy",
      "organizations:*",
      "account:*",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "limite" {
  name   = "limite-permisos-aplicaciones"
  policy = data.aws_iam_policy_document.limite.json
}

# ------------------------------------------------------------------ Rol de PLAN: lo asume un pull request o la rama principal (solo lectura)
data "aws_iam_policy_document" "confianza_plan" {
  for_each = var.entornos

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.emisor}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.emisor}:sub"
      values = [
        "repo:${var.repositorio}:pull_request",
        "repo:${var.repositorio}:ref:refs/heads/main",
      ]
    }
  }
}

resource "aws_iam_role" "plan" {
  for_each = var.entornos

  name                 = "terraform-plan-${each.key}"
  assume_role_policy   = data.aws_iam_policy_document.confianza_plan[each.key].json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "plan_lectura" {
  for_each = var.entornos

  role       = aws_iam_role.plan[each.key].name
  policy_arn = "arn:${local.particion}:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "plan_estado" {
  for_each = var.entornos

  role       = aws_iam_role.plan[each.key].name
  policy_arn = var.politicas_estado_plan[each.key]
}

# ------------------------------------------------------------------ Rol de APPLY: solo una ejecución en el ENTORNO protegido
data "aws_iam_policy_document" "confianza_apply" {
  for_each = var.entornos

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.emisor}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.emisor}:sub"
      values   = ["repo:${var.repositorio}:environment:${each.key}"]
    }
  }
}

data "aws_iam_policy_document" "apply" {
  statement {
    sid       = "ServiciosDelComponente"
    actions   = [for s in var.servicios_permitidos : "${s}:*"]
    resources = ["*"]
  }

  statement {
    sid       = "CrearRolesSoloConLimite"
    actions   = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"]
    resources = ["arn:${local.particion}:iam::${local.cuenta}:role/app-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.limite.arn]
    }
  }

  statement {
    sid = "AdministrarRolesDeAplicacion"
    actions = [
      "iam:GetRole",
      "iam:DeleteRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:PassRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListAttachedRolePolicies",
    ]
    resources = ["arn:${local.particion}:iam::${local.cuenta}:role/app-*"]
  }

  statement {
    sid    = "NoTocarElLimite"
    effect = "Deny"
    actions = [
      "iam:DeleteRolePermissionsBoundary",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicy",
      "iam:DeletePolicyVersion",
      "iam:SetDefaultPolicyVersion",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "apply" {
  name   = "terraform-apply-componente"
  policy = data.aws_iam_policy_document.apply.json
}

resource "aws_iam_role" "apply" {
  for_each = var.entornos

  name                 = "terraform-apply-${each.key}"
  assume_role_policy   = data.aws_iam_policy_document.confianza_apply[each.key].json
  max_session_duration = 7200
}

resource "aws_iam_role_policy_attachment" "apply_permisos" {
  for_each = var.entornos

  role       = aws_iam_role.apply[each.key].name
  policy_arn = aws_iam_policy.apply.arn
}

resource "aws_iam_role_policy_attachment" "apply_estado" {
  for_each = var.entornos

  role       = aws_iam_role.apply[each.key].name
  policy_arn = var.politicas_estado_apply[each.key]
}

output "roles_plan" {
  value = { for k, r in aws_iam_role.plan : k => r.arn }
}

output "roles_apply" {
  value = { for k, r in aws_iam_role.apply : k => r.arn }
}

output "limite_de_permisos" {
  value = aws_iam_policy.limite.arn
}
