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

variable "red_id" {
  type        = string
  description = "projects/<p>/global/networks/modalima-vpc"
}

# PSC para APIs de Google: una IP propia
resource "google_compute_global_address" "psc_apis" {
  name         = "psc-apis"
  purpose      = "PRIVATE_SERVICE_CONNECT"
  address_type = "INTERNAL"
  address      = "10.10.99.10"
  network      = var.red_id
}

resource "google_compute_global_forwarding_rule" "psc_apis" {
  name                  = "pscapis"
  target                = "all-apis"
  network               = var.red_id
  ip_address            = google_compute_global_address.psc_apis.id
  load_balancing_scheme = ""
}

resource "google_dns_managed_zone" "googleapis" {
  name       = "googleapis-privada"
  dns_name   = "googleapis.com."
  visibility = "private"
  private_visibility_config {
    networks {
      network_url = var.red_id
    }
  }
}

resource "google_dns_record_set" "comodin" {
  managed_zone = google_dns_managed_zone.googleapis.name
  name         = "*.googleapis.com."
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.psc_apis.address]
}

# PSA para Cloud SQL / Memorystore con IP privada
resource "google_compute_global_address" "psa" {
  name          = "rango-servicios-google"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  address       = "10.50.0.0"
  prefix_length = 16
  network       = var.red_id
}

resource "google_service_networking_connection" "psa" {
  network                 = var.red_id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psa.name]
}
