terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Se ejecuta SOLO en la cuenta de administración de la organización.
provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "regiones_permitidas" {
  type    = list(string)
  default = ["us-east-1", "sa-east-1"]
}

variable "bucket_logs" {
  type        = string
  description = "Bucket de la cuenta de archivo de logs que recibe el trail de la organización"
}

variable "cuentas" {
  description = "Una entrada por cuenta de carga. La clave es el nombre: {carga}-{entorno}"
  type = map(object({
    correo              = string
    ou                  = string # prod | noprod | sandbox
    equipo              = string
    centro_de_costos    = string
    presupuesto_mensual = number
    cidr                = string
  }))

  validation {
    condition     = alltrue([for n, _ in var.cuentas : can(regex("^[a-z][a-z0-9]{2,19}-(prod|stg|dev|sbx)$", n))])
    error_message = "El nombre debe ser {carga}-{prod|stg|dev|sbx}, en minúsculas (p. ej. pagos-prod)."
  }
  validation {
    condition     = alltrue([for _, c in var.cuentas : can(regex("^aws\\+[a-z0-9-]+@modalima\\.example$", c.correo))])
    error_message = "El correo debe ser un alias aws+{nombre}@modalima.example."
  }
  validation {
    condition     = alltrue([for n, c in var.cuentas : (endswith(n, "-prod") ? c.ou == "prod" : c.ou != "prod")])
    error_message = "Solo las cuentas -prod van en la OU prod."
  }
  validation {
    condition     = length(distinct([for _, c in var.cuentas : c.cidr])) == length(var.cuentas)
    error_message = "Cada cuenta debe tener un CIDR distinto (y sin solaparse: valídalo con el asignador)."
  }
  validation {
    condition     = alltrue([for _, c in var.cuentas : c.presupuesto_mensual > 0])
    error_message = "El presupuesto mensual debe ser positivo."
  }
}

data "aws_organizations_organization" "actual" {}

locals {
  raiz = data.aws_organizations_organization.actual.roots[0].id
  unidades = {
    seguridad       = "Seguridad"
    infraestructura = "Infraestructura"
    cargas          = "Cargas"
    sandbox         = "Sandbox"
  }
}

# --- Unidades organizativas ---
resource "aws_organizations_organizational_unit" "base" {
  for_each  = local.unidades
  name      = each.value
  parent_id = local.raiz
}

resource "aws_organizations_organizational_unit" "prod" {
  name      = "Prod"
  parent_id = aws_organizations_organizational_unit.base["cargas"].id
}

resource "aws_organizations_organizational_unit" "noprod" {
  name      = "NoProd"
  parent_id = aws_organizations_organizational_unit.base["cargas"].id
}

locals {
  ou_destino = {
    prod    = aws_organizations_organizational_unit.prod.id
    noprod  = aws_organizations_organizational_unit.noprod.id
    sandbox = aws_organizations_organizational_unit.base["sandbox"].id
  }
}

# --- Cuentas de carga (vending): cambiar el mapa = crear/mover cuentas por pull request ---
resource "aws_organizations_account" "carga" {
  for_each  = var.cuentas
  name      = each.key
  email     = each.value.correo
  parent_id = local.ou_destino[each.value.ou]
  role_name = "OrganizationAccountAccessRole"

  # Si se quita del código, la cuenta NO se cierra: solo deja de gestionarse.
  close_on_deletion = false

  tags = {
    equipo         = each.value.equipo
    centroDeCostos = each.value.centro_de_costos
    entorno        = split("-", each.key)[1]
    cidr           = each.value.cidr
    gestionadoPor  = "terraform"
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [role_name]
  }
}

# --- Barandas (SCP) ---
data "aws_iam_policy_document" "no_desactivar_controles" {
  statement {
    sid    = "NoSalirNiApagarAuditoria"
    effect = "Deny"
    actions = [
      "organizations:LeaveOrganization",
      "cloudtrail:StopLogging",
      "cloudtrail:DeleteTrail",
      "cloudtrail:UpdateTrail",
      "config:StopConfigurationRecorder",
      "config:DeleteConfigurationRecorder",
      "guardduty:DeleteDetector",
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "regiones" {
  statement {
    sid    = "SoloRegionesAprobadas"
    effect = "Deny"
    not_actions = [
      "iam:*", "organizations:*", "route53:*", "cloudfront:*", "support:*",
      "budgets:*", "ce:*", "sts:*", "waf:*", "wafv2:*", "globalaccelerator:*",
    ]
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestedRegion"
      values   = var.regiones_permitidas
    }
  }
}

resource "aws_organizations_policy" "no_desactivar_controles" {
  name    = "no-desactivar-controles"
  type    = "SERVICE_CONTROL_POLICY"
  content = data.aws_iam_policy_document.no_desactivar_controles.json
}

resource "aws_organizations_policy" "regiones" {
  name    = "solo-regiones-aprobadas"
  type    = "SERVICE_CONTROL_POLICY"
  content = data.aws_iam_policy_document.regiones.json
}

resource "aws_organizations_policy_attachment" "controles_en_raiz" {
  policy_id = aws_organizations_policy.no_desactivar_controles.id
  target_id = local.raiz
}

resource "aws_organizations_policy_attachment" "regiones_en_cargas" {
  policy_id = aws_organizations_policy.regiones.id
  target_id = aws_organizations_organizational_unit.base["cargas"].id
}

# --- Auditoría: un solo trail para toda la organización, hacia la cuenta de logs ---
resource "aws_cloudtrail" "organizacion" {
  name                          = "modalima-organizacion"
  s3_bucket_name                = var.bucket_logs
  is_organization_trail         = true
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true
}

# --- Presupuesto por cuenta (se define desde la cuenta de administración) ---
resource "aws_budgets_budget" "cuenta" {
  for_each     = var.cuentas
  name         = "presupuesto-${each.key}"
  budget_type  = "COST"
  limit_amount = tostring(each.value.presupuesto_mensual)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "LinkedAccount"
    values = [aws_organizations_account.carga[each.key].id]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [each.value.correo]
  }
}

output "cuentas" {
  value = { for n, a in aws_organizations_account.carga : n => a.id }
}
