# Módulo "microservicio": NSG de la app, grupo dinámico y política mínima.
terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 7.0"
    }
  }
}

variable "nombre" {
  type = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.nombre))
    error_message = "Nombre en minúsculas, 3 a 31 caracteres."
  }
}

variable "entorno" {
  type = string
  validation {
    condition     = contains(["prod", "no-prod"], var.entorno)
    error_message = "Entorno prod o no-prod."
  }
}

variable "compartimento_id" {
  type = string
}

variable "vcn_id" {
  type = string
}

variable "puerto" {
  type    = number
  default = 8080
}

variable "nsg_origen_id" {
  type        = string
  description = "NSG desde el que se acepta tráfico (balanceador)"
}

resource "oci_core_network_security_group" "app" {
  compartment_id = var.compartimento_id
  vcn_id         = var.vcn_id
  display_name   = "nsg-${var.nombre}-${var.entorno}"
}

resource "oci_core_network_security_group_security_rule" "entrada" {
  network_security_group_id = oci_core_network_security_group.app.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source_type               = "NETWORK_SECURITY_GROUP"
  source                    = var.nsg_origen_id
  tcp_options {
    destination_port_range {
      min = var.puerto
      max = var.puerto
    }
  }
}

output "nsg_id" {
  value = oci_core_network_security_group.app.id
}
