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
  region  = var.region
}

variable "proyecto" {
  type = string
}

variable "region" {
  type    = string
  default = "southamerica-west1"
}

variable "red" {
  type    = string
  default = "modalima-vpc"
}

variable "sa_app" {
  type        = string
  description = "Correo de la cuenta de servicio de la app"
}

# Solo el balanceador (rangos de los proxies/chequeos de Google) llega a la app
resource "google_compute_firewall" "lb_a_app" {
  name                    = "permitir-lb-a-app"
  network                 = var.red
  direction               = "INGRESS"
  priority                = 1000
  source_ranges           = ["130.211.0.0/22", "35.191.0.0/16"]
  target_service_accounts = [var.sa_app]

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# SSH administrativo solo por IAP
resource "google_compute_firewall" "iap_ssh" {
  name          = "permitir-iap-ssh"
  network       = var.red
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["bastion"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_address" "nat" {
  count  = 2
  name   = "nat-${count.index}"
  region = var.region
}

resource "google_compute_router" "router" {
  name    = "router-${var.region}"
  region  = var.region
  network = var.red
}

resource "google_compute_router_nat" "nat" {
  name                                = "nat-${var.region}"
  router                              = google_compute_router.router.name
  region                              = var.region
  nat_ip_allocate_option              = "MANUAL_ONLY"
  nat_ips                             = google_compute_address.nat[*].self_link
  source_subnetwork_ip_ranges_to_nat  = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  enable_dynamic_port_allocation      = true
  min_ports_per_vm                    = 256
  max_ports_per_vm                    = 4096
  enable_endpoint_independent_mapping = false

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
