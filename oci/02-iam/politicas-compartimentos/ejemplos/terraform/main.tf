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
  type        = string
  default     = "us-ashburn-1"
  description = "Región home: IAM se administra desde ella"
}

variable "tenancy_ocid" {
  type = string
}

# Compartimentos
resource "oci_identity_compartment" "tienda" {
  compartment_id = var.tenancy_ocid
  name           = "tienda"
  description    = "Sistema de tienda en línea"
  enable_delete  = false
}

resource "oci_identity_compartment" "prod" {
  compartment_id = oci_identity_compartment.tienda.id
  name           = "tienda-prod"
  description    = "Producción"
  enable_delete  = false
}

resource "oci_identity_compartment" "dev" {
  compartment_id = oci_identity_compartment.tienda.id
  name           = "tienda-dev"
  description    = "Desarrollo"
  enable_delete  = false
}

# Grupos (en el dominio por defecto)
resource "oci_identity_group" "desarrollo" {
  compartment_id = var.tenancy_ocid
  name           = "Desarrollo"
  description    = "Equipo de desarrollo de la tienda"
}

resource "oci_identity_group" "auditores" {
  compartment_id = var.tenancy_ocid
  name           = "Auditores"
  description    = "Lectura transversal"
}

# Políticas pequeñas, una por equipo
resource "oci_identity_policy" "desarrollo" {
  compartment_id = oci_identity_compartment.tienda.id
  name           = "tienda-desarrollo"
  description    = "Desarrollo gestiona dev y solo lee prod"
  statements = [
    "Allow group ${oci_identity_group.desarrollo.name} to manage instance-family in compartment ${oci_identity_compartment.dev.name}",
    "Allow group ${oci_identity_group.desarrollo.name} to manage object-family in compartment ${oci_identity_compartment.dev.name}",
    "Allow group ${oci_identity_group.desarrollo.name} to read all-resources in compartment ${oci_identity_compartment.prod.name}",
  ]
}

resource "oci_identity_policy" "auditores" {
  compartment_id = var.tenancy_ocid
  name           = "auditores-lectura"
  description    = "Auditoría transversal de solo lectura"
  statements = [
    "Allow group ${oci_identity_group.auditores.name} to inspect all-resources in tenancy",
    "Allow group ${oci_identity_group.auditores.name} to read audit-events in tenancy",
  ]
}

output "compartimentos" {
  value = {
    tienda = oci_identity_compartment.tienda.id
    prod   = oci_identity_compartment.prod.id
    dev    = oci_identity_compartment.dev.id
  }
}
