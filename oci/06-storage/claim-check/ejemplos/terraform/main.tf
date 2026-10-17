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

variable "namespace" {
  type = string
}

resource "oci_objectstorage_bucket" "cargas" {
  compartment_id = var.compartimento_id
  namespace      = var.namespace
  name           = "cargas"
  access_type    = "NoPublicAccess"
}

# Retención más larga que el máximo de reintentos de la cola
resource "oci_objectstorage_object_lifecycle_policy" "cargas" {
  namespace = var.namespace
  bucket    = oci_objectstorage_bucket.cargas.name

  rules {
    name        = "borrar-a-los-7-dias"
    action      = "DELETE"
    is_enabled  = true
    time_amount = 7
    time_unit   = "DAYS"
    target      = "objects"
  }
}

resource "oci_queue_queue" "pedidos" {
  compartment_id                   = var.compartimento_id
  display_name                     = "pedidos-mayoristas"
  retention_in_seconds             = 345600
  visibility_in_seconds            = 120
  timeout_in_seconds               = 20
  dead_letter_queue_delivery_count = 5
}

output "endpoint_mensajes" {
  value = oci_queue_queue.pedidos.messages_endpoint
}
