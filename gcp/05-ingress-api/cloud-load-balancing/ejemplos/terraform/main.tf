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

variable "dominio" {
  type    = string
  default = "tienda.modalima.example"
}

variable "servicio_run" {
  type    = string
  default = "pedidos"
}

resource "google_compute_global_address" "tienda" {
  name = "ip-tienda"
}

resource "google_compute_managed_ssl_certificate" "tienda" {
  name = "cert-tienda"
  managed {
    domains = [var.dominio]
  }
}

resource "google_compute_region_network_endpoint_group" "api" {
  name                  = "neg-api"
  region                = var.region
  network_endpoint_type = "SERVERLESS"
  cloud_run {
    service = var.servicio_run
  }
}

resource "google_compute_backend_service" "api" {
  name                  = "api"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  protocol              = "HTTPS"

  backend {
    group = google_compute_region_network_endpoint_group.api.id
  }

  log_config {
    enable      = true
    sample_rate = 0.5
  }
}

resource "google_compute_url_map" "tienda" {
  name            = "tienda"
  default_service = google_compute_backend_service.api.id

  host_rule {
    hosts        = [var.dominio]
    path_matcher = "rutas"
  }

  path_matcher {
    name            = "rutas"
    default_service = google_compute_backend_service.api.id

    path_rule {
      paths   = ["/api/*"]
      service = google_compute_backend_service.api.id
    }
  }

  test {
    host    = var.dominio
    path    = "/api/pedidos"
    service = google_compute_backend_service.api.id
  }
}

resource "google_compute_target_https_proxy" "tienda" {
  name             = "https-tienda"
  url_map          = google_compute_url_map.tienda.id
  ssl_certificates = [google_compute_managed_ssl_certificate.tienda.id]
}

resource "google_compute_global_forwarding_rule" "https" {
  name                  = "https-tienda"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  target                = google_compute_target_https_proxy.tienda.id
  ip_address            = google_compute_global_address.tienda.id
  port_range            = "443"
}

# Redirección HTTP → HTTPS
resource "google_compute_url_map" "redireccion" {
  name = "a-https"
  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

resource "google_compute_target_http_proxy" "redireccion" {
  name    = "http-tienda"
  url_map = google_compute_url_map.redireccion.id
}

resource "google_compute_global_forwarding_rule" "http" {
  name                  = "http-tienda"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  target                = google_compute_target_http_proxy.redireccion.id
  ip_address            = google_compute_global_address.tienda.id
  port_range            = "80"
}
