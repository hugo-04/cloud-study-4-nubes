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
  default = "us-ashburn-1"
}

variable "tenancy_ocid" {
  type = string
}

variable "compartimento_prod_id" {
  type = string
}

variable "compartimento_prod_nombre" {
  type    = string
  default = "tienda-prod"
}

# Regla acotada: ALL + compartimento + etiqueta
resource "oci_identity_dynamic_group" "app_tienda" {
  compartment_id = var.tenancy_ocid
  name           = "app-tienda-prod"
  description    = "VM de la tienda en producción"
  matching_rule  = "ALL {instance.compartment.id = '${var.compartimento_prod_id}', tag.app.nombre.value = 'tienda'}"
}

# Funciones del mismo compartimento
resource "oci_identity_dynamic_group" "funciones_tienda" {
  compartment_id = var.tenancy_ocid
  name           = "funciones-tienda-prod"
  description    = "Funciones de la tienda en producción"
  matching_rule  = "ALL {resource.type = 'fnfunc', resource.compartment.id = '${var.compartimento_prod_id}'}"
}

# Política mínima: leer un solo bucket
resource "oci_identity_policy" "app_tienda" {
  compartment_id = var.compartimento_prod_id
  name           = "app-tienda-lee-comprobantes"
  description    = "La aplicación lee objetos de un bucket"
  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.app_tienda.name} to read objects in compartment ${var.compartimento_prod_nombre} where target.bucket.name = 'comprobantes'",
  ]
}
