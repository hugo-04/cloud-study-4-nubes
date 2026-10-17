terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Budgets, Cost Explorer y Cost Anomaly Detection son servicios globales: se gestionan desde us-east-1.
provider "aws" {
  region = "us-east-1"
}

variable "correos_finanzas" {
  description = "Destinatarios de los avisos de presupuesto"
  type        = list(string)
  default     = ["finanzas@modalima.example"]
}

variable "limite_mensual_total" {
  description = "Presupuesto mensual total (USD)"
  type        = number
  default     = 6000
}

variable "equipos" {
  description = "Presupuesto mensual (USD) por valor de la etiqueta equipo"
  type        = map(number)
  default = {
    pagos     = 1500
    catalogo  = 1200
    logistica = 800
  }
}

variable "limite_sandbox" {
  description = "Presupuesto mensual del sandbox (USD)"
  type        = number
  default     = 300
}

variable "rol_sandbox" {
  description = "Rol (existente) al que se aplica la política de bloqueo cuando el sandbox llega al 100 %"
  type        = string
  default     = "dev-sandbox"
}

variable "umbral_anomalia_usd" {
  description = "Impacto mínimo (USD) para avisar de una anomalía"
  type        = number
  default     = 100
}

data "aws_caller_identity" "actual" {}
data "aws_partition" "actual" {}

# ---------------------------------------------------------------- Tópico de alertas
resource "aws_sns_topic" "costos" {
  name = "alertas-costos"
}

data "aws_iam_policy_document" "sns_costos" {
  statement {
    sid       = "PermitirBudgets"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.costos.arn]

    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.actual.account_id]
    }
  }

  statement {
    sid       = "PermitirAnomalias"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.costos.arn]

    principals {
      type        = "Service"
      identifiers = ["costalerts.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic_policy" "costos" {
  arn    = aws_sns_topic.costos.arn
  policy = data.aws_iam_policy_document.sns_costos.json
}

# ---------------------------------------------------------------- Etiquetas de asignación de costos
# Sin activarlas en Facturación, las etiquetas NO aparecen en los costos.
resource "aws_ce_cost_allocation_tag" "activas" {
  for_each = toset(["equipo", "entorno"])
  tag_key  = each.key
  status   = "Active"
}

# ---------------------------------------------------------------- Presupuesto total
resource "aws_budgets_budget" "total" {
  name         = "total-mensual"
  budget_type  = "COST"
  limit_amount = tostring(var.limite_mensual_total)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_types {
    include_credit = false
    include_refund = false
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.correos_finanzas
    subscriber_sns_topic_arns  = [aws_sns_topic.costos.arn]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.correos_finanzas
    subscriber_sns_topic_arns  = [aws_sns_topic.costos.arn]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.correos_finanzas
    subscriber_sns_topic_arns  = [aws_sns_topic.costos.arn]
  }
}

# ---------------------------------------------------------------- Un presupuesto por equipo (filtro por etiqueta)
resource "aws_budgets_budget" "equipo" {
  for_each = var.equipos

  name         = "equipo-${each.key}-mensual"
  budget_type  = "COST"
  limit_amount = tostring(each.value)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = [format("user:equipo$%s", each.key)]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.correos_finanzas
    subscriber_sns_topic_arns  = [aws_sns_topic.costos.arn]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.correos_finanzas
    subscriber_sns_topic_arns  = [aws_sns_topic.costos.arn]
  }

  depends_on = [aws_ce_cost_allocation_tag.activas]
}

# ---------------------------------------------------------------- Sandbox con freno (acción de presupuesto)
resource "aws_budgets_budget" "sandbox" {
  name         = "sandbox-mensual"
  budget_type  = "COST"
  limit_amount = tostring(var.limite_sandbox)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = ["user:entorno$sandbox"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.correos_finanzas
    subscriber_sns_topic_arns  = [aws_sns_topic.costos.arn]
  }

  depends_on = [aws_ce_cost_allocation_tag.activas]
}

data "aws_iam_policy_document" "bloqueo" {
  statement {
    sid    = "NoCrearRecursosCaros"
    effect = "Deny"
    actions = [
      "ec2:RunInstances",
      "rds:CreateDBInstance",
      "rds:CreateDBCluster",
      "eks:CreateCluster",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "bloqueo_sandbox" {
  name        = "bloqueo-por-presupuesto"
  description = "Se adjunta al rol del sandbox cuando el presupuesto llega al 100 %"
  policy      = data.aws_iam_policy_document.bloqueo.json
}

data "aws_iam_policy_document" "confianza_budgets" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "accion_presupuesto" {
  name               = "budgets-accion-bloqueo"
  assume_role_policy = data.aws_iam_policy_document.confianza_budgets.json
}

data "aws_iam_policy_document" "permisos_accion" {
  statement {
    sid       = "AdjuntarSoloElBloqueoAlRolSandbox"
    actions   = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"]
    resources = ["arn:${data.aws_partition.actual.partition}:iam::${data.aws_caller_identity.actual.account_id}:role/${var.rol_sandbox}"]

    condition {
      test     = "ArnEquals"
      variable = "iam:PolicyARN"
      values   = [aws_iam_policy.bloqueo_sandbox.arn]
    }
  }
}

resource "aws_iam_role_policy" "accion_presupuesto" {
  name   = "adjuntar-bloqueo"
  role   = aws_iam_role.accion_presupuesto.id
  policy = data.aws_iam_policy_document.permisos_accion.json
}

resource "aws_budgets_budget_action" "bloquear_sandbox" {
  budget_name        = aws_budgets_budget.sandbox.name
  action_type        = "APPLY_IAM_POLICY"
  approval_model     = "MANUAL" # al principio, una persona aprueba antes de que se aplique
  notification_type  = "ACTUAL"
  execution_role_arn = aws_iam_role.accion_presupuesto.arn

  action_threshold {
    action_threshold_type  = "PERCENTAGE"
    action_threshold_value = 100
  }

  definition {
    iam_action_definition {
      policy_arn = aws_iam_policy.bloqueo_sandbox.arn
      roles      = [var.rol_sandbox]
    }
  }

  subscriber {
    address           = var.correos_finanzas[0]
    subscription_type = "EMAIL"
  }
}

# ---------------------------------------------------------------- Categoría de costos
resource "aws_ce_cost_category" "producto" {
  name          = "producto"
  rule_version  = "CostCategoryExpression.v1"
  default_value = "compartido"

  rule {
    value = "tienda-online"

    rule {
      tags {
        key           = "equipo"
        values        = ["pagos", "catalogo", "logistica"]
        match_options = ["EQUALS"]
      }
    }
  }
}

# ---------------------------------------------------------------- Detección de anomalías
resource "aws_ce_anomaly_monitor" "servicios" {
  name              = "por-servicio"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

# Inmediata: solo admite SNS como destino.
resource "aws_ce_anomaly_subscription" "inmediata" {
  name             = "anomalias-inmediatas"
  frequency        = "IMMEDIATE"
  monitor_arn_list = [aws_ce_anomaly_monitor.servicios.arn]

  subscriber {
    type    = "SNS"
    address = aws_sns_topic.costos.arn
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = [tostring(var.umbral_anomalia_usd)]
    }
  }

  depends_on = [aws_sns_topic_policy.costos]
}

# Resumen diario por correo.
resource "aws_ce_anomaly_subscription" "resumen" {
  name             = "anomalias-resumen-diario"
  frequency        = "DAILY"
  monitor_arn_list = [aws_ce_anomaly_monitor.servicios.arn]

  subscriber {
    type    = "EMAIL"
    address = var.correos_finanzas[0]
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = ["20"]
    }
  }
}

output "topico_alertas" {
  value = aws_sns_topic.costos.arn
}
