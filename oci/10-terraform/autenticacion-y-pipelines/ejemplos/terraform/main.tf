terraform {
  required_version = ">= 1.5"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 7.0"
    }
  }
}

# En el runner: auth por instancia (sin llaves en disco)
provider "oci" {
  region = var.region
  auth   = "InstancePrincipal"
}

variable "region" {
  type    = string
  default = "sa-saopaulo-1"
}

variable "tenancy_id" {
  type = string
}

variable "compartimento_runners_id" {
  type = string
}

variable "entornos" {
  type    = set(string)
  default = ["prod", "no-prod"]
}

# Un grupo dinámico por entorno: las VMs runner llevan la etiqueta Gobierno.entorno correspondiente
resource "oci_identity_dynamic_group" "runner" {
  for_each       = var.entornos
  compartment_id = var.tenancy_id
  name           = "runners-${each.key}"
  description    = "Runners de infraestructura de ${each.key}"
  matching_rule  = "ALL {instance.compartment.id = '${var.compartimento_runners_id}', tag.Gobierno.entorno.value = '${each.key}'}"
}

resource "oci_identity_policy" "runner" {
  for_each       = var.entornos
  compartment_id = var.tenancy_id
  name           = "runners-${each.key}"
  description    = "El runner de ${each.key} solo gestiona su compartimento"
  statements = [
    "Allow dynamic-group runners-${each.key} to manage all-resources in compartment modalima:${each.key}",
    "Allow dynamic-group runners-${each.key} to read all-resources in compartment red-compartida",
  ]
}
