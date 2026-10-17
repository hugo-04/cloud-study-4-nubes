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

variable "red" {
  type = string
}

# IP global reservada que referencia el Gateway (addresses: NamedAddress)
resource "google_compute_global_address" "gateway" {
  name = "ip-gateway-tienda"

  lifecycle {
    prevent_destroy = true
  }
}

# Chequeos y proxies del balanceador hacia los pods (NEG)
resource "google_compute_firewall" "chequeos_a_pods" {
  name          = "permitir-balanceador-a-pods"
  network       = var.red
  direction     = "INGRESS"
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }
}

output "ip_gateway" {
  value = google_compute_global_address.gateway.address
}
