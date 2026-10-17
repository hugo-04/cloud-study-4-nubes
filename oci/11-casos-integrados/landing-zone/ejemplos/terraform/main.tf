terraform {
  required_version = ">= 1.5"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 7.0"
    }
  }
}

provider "oci" {
  region = var.region_home
}

variable "region_home" {
  type    = string
  default = "sa-saopaulo-1"
}

variable "tenancy_id" {
  type = string
}

variable "unidad" {
  type    = string
  default = "tostaduria"
}

variable "cidr_unidad" {
  type        = string
  description = "Rango /16 libre propuesto por el planificador (por ejemplo 10.24.0.0/16)"
  validation {
    condition     = can(cidrhost(var.cidr_unidad, 0)) && endswith(var.cidr_unidad, "/16")
    error_message = "Debe ser un CIDR /16 válido."
  }
}

variable "presupuesto_mensual" {
  type    = number
  default = 1500
}

locals {
  entornos = {
    prod    = cidrsubnet(var.cidr_unidad, 1, 0)
    no-prod = cidrsubnet(var.cidr_unidad, 1, 1)
  }
}

resource "oci_identity_compartment" "unidad" {
  compartment_id = var.tenancy_id
  name           = var.unidad
  description    = "Unidad ${var.unidad}"
}

resource "oci_identity_compartment" "entorno" {
  for_each       = local.entornos
  compartment_id = oci_identity_compartment.unidad.id
  name           = each.key
  description    = "${var.unidad} ${each.key}"
}

resource "oci_core_vcn" "entorno" {
  for_each       = local.entornos
  compartment_id = oci_identity_compartment.entorno[each.key].id
  display_name   = "vcn-${var.unidad}-${each.key}"
  cidr_blocks    = [each.value]
  dns_label      = substr(replace("${var.unidad}${each.key}", "-", ""), 0, 15)
}

resource "oci_identity_group" "rol" {
  for_each       = toset(["admins", "devs"])
  compartment_id = var.tenancy_id
  name           = "${var.unidad}-${each.key}"
  description    = "${each.key} de ${var.unidad}"
}

resource "oci_identity_policy" "unidad" {
  compartment_id = var.tenancy_id
  name           = "${var.unidad}-acceso"
  description    = "Acceso de la unidad sin IAM ni red compartida"
  statements = [
    "Allow group ${var.unidad}-admins to manage all-resources in compartment ${var.unidad} where all {request.permission != 'POLICY_CREATE', request.permission != 'POLICY_UPDATE', request.permission != 'POLICY_DELETE'}",
    "Allow group ${var.unidad}-devs to manage all-resources in compartment ${var.unidad}:no-prod where all {request.permission != 'POLICY_CREATE', request.permission != 'POLICY_UPDATE', request.permission != 'POLICY_DELETE'}",
    "Allow group ${var.unidad}-devs to read all-resources in compartment ${var.unidad}:prod",
  ]
  depends_on = [oci_identity_group.rol, oci_identity_compartment.entorno]
}

resource "oci_limits_quota" "no_prod" {
  compartment_id = var.tenancy_id
  name           = "${var.unidad}-no-prod"
  description    = "Topes de no-prod"
  statements = [
    "zero gpu-family quotas in compartment ${var.unidad}:no-prod",
  ]
  depends_on = [oci_identity_compartment.entorno]
}

resource "oci_budget_budget" "unidad" {
  compartment_id = var.tenancy_id
  display_name   = "${var.unidad}-mensual"
  amount         = var.presupuesto_mensual
  reset_period   = "MONTHLY"
  target_type    = "COMPARTMENT"
  targets        = [oci_identity_compartment.unidad.id]
}

resource "oci_budget_alert_rule" "proyectado" {
  budget_id      = oci_budget_budget.unidad.id
  type           = "FORECAST"
  threshold      = 100
  threshold_type = "PERCENTAGE"
  recipients     = "finanzas@cafeandino.example"
}

output "vcns" {
  value = { for k, v in oci_core_vcn.entorno : k => v.cidr_blocks }
}
