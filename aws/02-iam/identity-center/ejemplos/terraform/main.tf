terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Debe ejecutarse en la REGIÓN DE ORIGEN de Identity Center (y en la cuenta de administración o la delegada)
provider "aws" {
  region = var.region_origen
}

variable "region_origen" {
  type    = string
  default = "us-east-1"
}

variable "cuentas" {
  description = "Nombres lógicos -> ID de cuenta."
  type        = map(string)
}

variable "grupos" {
  description = "Nombre de grupo (tal como llega por SCIM) a asignar."
  type        = set(string)
  default     = ["plataforma", "desarrollo-pedidos", "lectura-prod", "auditoria"]
}

data "aws_ssoadmin_instances" "this" {}

locals {
  instancia_arn = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  almacen_id    = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]

  # Conjuntos de permisos (nombre -> política administrada de AWS y duración de sesión)
  conjuntos = {
    AdministradorPlataforma = { politica = "arn:aws:iam::aws:policy/AdministratorAccess", sesion = "PT2H" }
    Desarrollo              = { politica = "arn:aws:iam::aws:policy/PowerUserAccess", sesion = "PT8H" }
    SoloLectura             = { politica = "arn:aws:iam::aws:policy/ReadOnlyAccess", sesion = "PT8H" }
    Auditoria               = { politica = "arn:aws:iam::aws:policy/SecurityAudit", sesion = "PT4H" }
  }

  # Matriz de asignaciones: grupo -> conjunto de permisos -> cuentas
  matriz = [
    { grupo = "plataforma", conjunto = "AdministradorPlataforma", cuenta = "dev" },
    { grupo = "plataforma", conjunto = "SoloLectura", cuenta = "prod" },
    { grupo = "desarrollo-pedidos", conjunto = "Desarrollo", cuenta = "dev" },
    { grupo = "lectura-prod", conjunto = "SoloLectura", cuenta = "prod" },
    { grupo = "auditoria", conjunto = "Auditoria", cuenta = "dev" },
    { grupo = "auditoria", conjunto = "Auditoria", cuenta = "prod" },
  ]
}

resource "aws_ssoadmin_permission_set" "p" {
  for_each = local.conjuntos

  name             = each.key
  instance_arn     = local.instancia_arn
  session_duration = each.value.sesion
  description      = "Conjunto ${each.key} (gestionado por Terraform)"
}

resource "aws_ssoadmin_managed_policy_attachment" "p" {
  for_each = local.conjuntos

  instance_arn       = local.instancia_arn
  managed_policy_arn = each.value.politica
  permission_set_arn = aws_ssoadmin_permission_set.p[each.key].arn
}

# Política en línea adicional: la administración de plataforma no puede borrar la bóveda de claves de auditoría
data "aws_iam_policy_document" "recorte_admin" {
  statement {
    sid       = "ProtegerRegistroDeAuditoria"
    effect    = "Deny"
    actions   = ["cloudtrail:StopLogging", "cloudtrail:DeleteTrail"]
    resources = ["*"]
  }
}

resource "aws_ssoadmin_permission_set_inline_policy" "admin" {
  instance_arn       = local.instancia_arn
  permission_set_arn = aws_ssoadmin_permission_set.p["AdministradorPlataforma"].arn
  inline_policy      = data.aws_iam_policy_document.recorte_admin.json
}

# Los grupos llegan por SCIM; aquí solo se buscan
data "aws_identitystore_group" "g" {
  for_each = var.grupos

  identity_store_id = local.almacen_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "DisplayName"
      attribute_value = each.key
    }
  }
}

resource "aws_ssoadmin_account_assignment" "a" {
  for_each = { for m in local.matriz : "${m.grupo}-${m.conjunto}-${m.cuenta}" => m }

  instance_arn       = local.instancia_arn
  permission_set_arn = aws_ssoadmin_permission_set.p[each.value.conjunto].arn

  principal_id   = data.aws_identitystore_group.g[each.value.grupo].group_id
  principal_type = "GROUP"

  target_id   = var.cuentas[each.value.cuenta]
  target_type = "AWS_ACCOUNT"
}
