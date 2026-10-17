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

variable "correo_guardia" {
  type = string
}

variable "webhook_despacho" {
  type        = string
  description = "Endpoint HTTPS que confirma la suscripción"
}

resource "oci_ons_notification_topic" "criticas" {
  compartment_id = var.compartimento_id
  name           = "alertas-criticas-tienda"
  description    = "Caídas y errores que despiertan a la guardia"
}

resource "oci_ons_notification_topic" "pedidos" {
  compartment_id = var.compartimento_id
  name           = "pedidos-pagados"
  description    = "Evento de negocio para sistemas internos"
}

resource "oci_ons_subscription" "guardia" {
  compartment_id = var.compartimento_id
  topic_id       = oci_ons_notification_topic.criticas.id
  protocol       = "EMAIL"
  endpoint       = var.correo_guardia
}

resource "oci_ons_subscription" "despacho" {
  compartment_id = var.compartimento_id
  topic_id       = oci_ons_notification_topic.pedidos.id
  protocol       = "CUSTOM_HTTPS"
  endpoint       = var.webhook_despacho
}

output "tema_criticas" {
  value = oci_ons_notification_topic.criticas.id
}
