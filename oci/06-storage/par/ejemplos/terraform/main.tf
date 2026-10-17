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

variable "namespace" {
  type = string
}

variable "bucket" {
  type    = string
  default = "entregas-proveedores"
}

variable "proveedores" {
  type    = set(string)
  default = ["tostaduria-cusco", "empaques-lima"]
}

variable "vence" {
  type        = string
  description = "RFC3339; renueva aplicando con una fecha nueva (por ejemplo, cada semana desde el pipeline)"
}

# Una PAR por proveedor: solo escribe bajo su prefijo, sin listar
resource "oci_objectstorage_preauthrequest" "proveedor" {
  for_each              = var.proveedores
  namespace             = var.namespace
  bucket                = var.bucket
  name                  = "entrega-${each.key}"
  access_type           = "AnyObjectWrite"
  object_name           = "entradas/${each.key}/"
  bucket_listing_action = "Deny"
  time_expires          = var.vence
}

output "uris" {
  description = "Entrégalas por un canal seguro; Terraform las guarda en el estado (protégelo)"
  value       = { for k, v in oci_objectstorage_preauthrequest.proveedor : k => v.access_uri }
  sensitive   = true
}
