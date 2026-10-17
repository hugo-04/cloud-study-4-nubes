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
  region = var.region
}

variable "region" {
  type    = string
  default = "sa-saopaulo-1"
}

variable "tenancy_id" {
  type = string
}

resource "oci_identity_compartment" "modalima" {
  compartment_id = var.tenancy_id
  name           = "modalima"
  description    = "Unidad de negocio ModaLima"
}

resource "oci_identity_compartment" "entorno" {
  for_each       = toset(["prod", "no-prod"])
  compartment_id = oci_identity_compartment.modalima.id
  name           = each.key
  description    = "Entorno ${each.key}"
}

resource "oci_identity_tag_namespace" "gobierno" {
  compartment_id = var.tenancy_id
  name           = "Gobierno"
  description    = "Etiquetas obligatorias de gobierno"
}

resource "oci_identity_tag" "centro_costo" {
  tag_namespace_id = oci_identity_tag_namespace.gobierno.id
  name             = "centro_costo"
  description      = "Producto que paga el recurso"
  is_cost_tracking = true

  validator {
    validator_type = "ENUM"
    values         = ["tienda", "pagos", "logistica", "plataforma"]
  }
}

resource "oci_identity_tag" "entorno" {
  tag_namespace_id = oci_identity_tag_namespace.gobierno.id
  name             = "entorno"
  description      = "prod o no-prod"

  validator {
    validator_type = "ENUM"
    values         = ["prod", "no-prod"]
  }
}

resource "oci_identity_tag" "creado_por" {
  tag_namespace_id = oci_identity_tag_namespace.gobierno.id
  name             = "creado_por"
  description      = "Quién creó el recurso (se llena sola)"
}

# Obligatoria: el creador debe elegir el centro de costo
resource "oci_identity_tag_default" "centro_costo" {
  for_each          = oci_identity_compartment.entorno
  compartment_id    = each.value.id
  tag_definition_id = oci_identity_tag.centro_costo.id
  value             = "tienda"
  is_required       = true
}

# Automáticas
resource "oci_identity_tag_default" "entorno" {
  for_each          = oci_identity_compartment.entorno
  compartment_id    = each.value.id
  tag_definition_id = oci_identity_tag.entorno.id
  value             = each.key
  is_required       = false
}

resource "oci_identity_tag_default" "creado_por" {
  for_each          = oci_identity_compartment.entorno
  compartment_id    = each.value.id
  tag_definition_id = oci_identity_tag.creado_por.id
  value             = "$${iam.principal.name}"
  is_required       = false
}

resource "oci_limits_quota" "no_prod" {
  compartment_id = var.tenancy_id
  name           = "cuotas-no-prod"
  description    = "Topes de no producción"
  statements = [
    "zero gpu-family quotas in compartment modalima:no-prod",
    "set compute-core quota standard-e5-core-count to 16 in compartment modalima:no-prod",
    "set database quota adw-ecpu-count to 4 in compartment modalima:no-prod",
  ]
}
