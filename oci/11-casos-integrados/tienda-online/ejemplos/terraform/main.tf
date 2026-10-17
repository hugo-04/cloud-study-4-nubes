# Flujo de eventos de la tienda: cola de facturación con DLQ, tema de pedidos pagados y permisos de los pods.
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

variable "cluster_id" {
  type = string
}

variable "webhook_despacho" {
  type = string
}

resource "oci_queue_queue" "facturacion" {
  compartment_id                   = var.compartimento_id
  display_name                     = "pedidos-pagados-facturacion"
  retention_in_seconds             = 345600
  visibility_in_seconds            = 120
  timeout_in_seconds               = 20
  dead_letter_queue_delivery_count = 5
}

resource "oci_ons_notification_topic" "pedido_pagado" {
  compartment_id = var.compartimento_id
  name           = "pedido-pagado"
}

resource "oci_ons_subscription" "despacho" {
  compartment_id = var.compartimento_id
  topic_id       = oci_ons_notification_topic.pedido_pagado.id
  protocol       = "CUSTOM_HTTPS"
  endpoint       = var.webhook_despacho
}

# Workload identity: solo la cuenta de servicio "pedidos" del namespace "tienda" publica
resource "oci_identity_policy" "pedidos" {
  compartment_id = var.compartimento_id
  name           = "pods-pedidos-publican"
  description    = "El relay del outbox publica en la cola y el tema"
  statements = [
    "Allow any-user to use queues in compartment id ${var.compartimento_id} where all {request.principal.type = 'workload', request.principal.namespace = 'tienda', request.principal.service_account = 'pedidos', request.principal.cluster_id = '${var.cluster_id}', target.queue.id = '${oci_queue_queue.facturacion.id}'}",
    "Allow any-user to use ons-topics in compartment id ${var.compartimento_id} where all {request.principal.type = 'workload', request.principal.namespace = 'tienda', request.principal.service_account = 'pedidos', request.principal.cluster_id = '${var.cluster_id}', target.topic.id = '${oci_ons_notification_topic.pedido_pagado.id}'}",
    "Allow any-user to use queues in compartment id ${var.compartimento_id} where all {request.principal.type = 'workload', request.principal.namespace = 'tienda', request.principal.service_account = 'facturacion', request.principal.cluster_id = '${var.cluster_id}', target.queue.id = '${oci_queue_queue.facturacion.id}'}",
  ]
}

output "endpoint_cola" {
  value = oci_queue_queue.facturacion.messages_endpoint
}
