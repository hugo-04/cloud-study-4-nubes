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

variable "compartimento_id" {
  type = string
}

variable "subred_id" {
  type        = string
  description = "Subred PRIVADA con salida por NAT o puerta de servicios"
}

variable "imagen" {
  type        = string
  description = "Ejemplo: sa-saopaulo-1.ocir.io/NAMESPACE/normalizador-pedido:0.0.1"
}

resource "oci_functions_application" "tienda" {
  compartment_id = var.compartimento_id
  display_name   = "tienda-funciones"
  subnet_ids     = [var.subred_id]
  shape          = "GENERIC_X86"
}

resource "oci_functions_function" "normalizador" {
  application_id     = oci_functions_application.tienda.id
  display_name       = "normalizador-pedido"
  image              = var.imagen
  memory_in_mbs      = 256
  timeout_in_seconds = 30

  provisioned_concurrency_config {
    strategy = "CONSTANT"
    count    = 20
  }
}

# Grupo dinámico de las funciones de este compartimento
resource "oci_identity_dynamic_group" "funciones" {
  compartment_id = var.compartimento_id
  name           = "funciones-tienda"
  description    = "Funciones de la tienda"
  matching_rule  = "ALL {resource.type = 'fnfunc', resource.compartment.id = '${var.compartimento_id}'}"
}
