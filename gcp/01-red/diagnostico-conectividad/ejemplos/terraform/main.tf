terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
  }
}

provider "google" {
  project = var.proyecto
}

variable "proyecto" {
  type = string
}

variable "vm_pedidos" {
  type        = string
  description = "projects/<p>/zones/<z>/instances/pedidos-1"
}

variable "ip_cloudsql" {
  type = string
}

# Prueba guardada como código: se re-ejecuta tras cada cambio de red
resource "google_network_management_connectivity_test" "pedidos_a_sql" {
  name     = "pedidos-a-cloudsql"
  protocol = "TCP"

  source {
    instance = var.vm_pedidos
  }

  destination {
    ip_address = var.ip_cloudsql
    port       = 5432
  }
}
