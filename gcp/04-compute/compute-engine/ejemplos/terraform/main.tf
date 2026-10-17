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

variable "subred" {
  type = string
}

variable "imagen" {
  type        = string
  description = "Imagen endurecida, por ejemplo projects/<p>/global/images/family/base-modalima"
}

resource "google_service_account" "erp" {
  account_id   = "erp-modalima"
  display_name = "ERP"
}

resource "google_compute_instance_template" "erp" {
  name_prefix  = "erp-"
  machine_type = "e2-standard-4"
  tags         = ["erp"]

  disk {
    source_image = var.imagen
    auto_delete  = true
    boot         = true
    disk_size_gb = 50
  }

  network_interface {
    subnetwork = var.subred
    # sin access_config: sin IP externa
  }

  service_account {
    email  = google_service_account.erp.email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  labels = {
    centro_costo = "plataforma"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_health_check" "erp" {
  name                = "erp-salud"
  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3
  http_health_check {
    port         = 8080
    request_path = "/salud"
  }
}

resource "google_compute_region_instance_group_manager" "erp" {
  name               = "erp"
  region             = var.region
  base_instance_name = "erp"
  target_size        = 1

  version {
    instance_template = google_compute_instance_template.erp.id
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.erp.id
    initial_delay_sec = 300
  }

  update_policy {
    type                  = "PROACTIVE"
    minimal_action        = "REPLACE"
    max_surge_fixed       = 3
    max_unavailable_fixed = 0
  }
}
