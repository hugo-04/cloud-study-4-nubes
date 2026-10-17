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

variable "lb_id" {
  type = string
}

variable "correo_guardia" {
  type = string
}

resource "oci_ons_notification_topic" "guardia" {
  compartment_id = var.compartimento_id
  name           = "guardia-tienda"
}

resource "oci_ons_subscription" "guardia" {
  compartment_id = var.compartimento_id
  topic_id       = oci_ons_notification_topic.guardia.id
  protocol       = "EMAIL"
  endpoint       = var.correo_guardia
}

# Síntoma 1: errores 5xx en el LB (verifica nombres de métricas del namespace oci_lbaas)
resource "oci_monitoring_alarm" "errores_5xx" {
  compartment_id               = var.compartimento_id
  metric_compartment_id        = var.compartimento_id
  display_name                 = "SEV1 checkout: 5xx en el LB"
  namespace                    = "oci_lbaas"
  query                        = "HttpResponses5xx[1m]{resourceId = \"${var.lb_id}\"}.sum() > 50"
  severity                     = "CRITICAL"
  destinations                 = [oci_ons_notification_topic.guardia.id]
  is_enabled                   = true
  pending_duration             = "PT3M"
  repeat_notification_duration = "PT15M"
  body                         = "Errores 5xx sostenidos en el LB de la tienda. Runbook: primeros 5 minutos."
}

# Síntoma 2: backends no sanos
resource "oci_monitoring_alarm" "backends" {
  compartment_id        = var.compartimento_id
  metric_compartment_id = var.compartimento_id
  display_name          = "SEV2 tienda: backends no sanos"
  namespace             = "oci_lbaas"
  query                 = "UnHealthyBackendServers[1m]{resourceId = \"${var.lb_id}\"}.max() > 0"
  severity              = "ERROR"
  destinations          = [oci_ons_notification_topic.guardia.id]
  is_enabled            = true
  pending_duration      = "PT5M"
}
