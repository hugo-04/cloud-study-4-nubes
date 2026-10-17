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

variable "llave_id" {
  type    = string
  default = null
}

resource "oci_queue_queue" "facturacion" {
  compartment_id                   = var.compartimento_id
  display_name                     = "facturacion"
  retention_in_seconds             = 345600 # 4 días
  visibility_in_seconds            = 120
  timeout_in_seconds               = 20
  dead_letter_queue_delivery_count = 5
  custom_encryption_key_id         = var.llave_id

  freeform_tags = {
    proyecto = "modalima"
  }
}

resource "oci_identity_dynamic_group" "consumidores" {
  compartment_id = var.compartimento_id
  name           = "consumidores-facturacion"
  description    = "Pods/instancias que consumen la cola de facturación"
  matching_rule  = "ALL {instance.compartment.id = '${var.compartimento_id}'}"
}

resource "oci_identity_policy" "cola" {
  compartment_id = var.compartimento_id
  name           = "cola-facturacion"
  description    = "Consumo de la cola de facturación"
  statements = [
    "Allow dynamic-group consumidores-facturacion to use queues in compartment id ${var.compartimento_id} where target.queue.id = '${oci_queue_queue.facturacion.id}'",
  ]
}

output "messages_endpoint" {
  value = oci_queue_queue.facturacion.messages_endpoint
}
