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

variable "compartimento_red" {
  type = string
}

variable "entorno" {
  type = string
}

variable "subredes" {
  type        = map(string)
  description = "Nombre -> OCID de las subredes a las que se activan registros de flujo"
}

variable "retencion_dias" {
  type    = number
  default = 30
  validation {
    condition     = contains([30, 60, 90, 120, 150, 180], var.retencion_dias)
    error_message = "El grupo de logs de OCI admite retenciones de 30 a 180 días en pasos de 30."
  }
}

resource "oci_logging_log_group" "flujos" {
  compartment_id = var.compartimento_red
  display_name   = "${var.entorno}-flujos-vcn"
  description    = "Registros de flujo de las subredes críticas"
}

resource "oci_logging_log" "flujo" {
  for_each           = var.subredes
  display_name       = "${var.entorno}-flujo-${each.key}"
  log_group_id       = oci_logging_log_group.flujos.id
  log_type           = "SERVICE"
  is_enabled         = true
  retention_duration = var.retencion_dias
  configuration {
    compartment_id = var.compartimento_red
    source {
      category    = "all"
      resource    = each.value
      service     = "flowlogs"
      source_type = "OCISERVICE"
    }
  }
}

output "grupo_de_logs" {
  value = oci_logging_log_group.flujos.id
}
