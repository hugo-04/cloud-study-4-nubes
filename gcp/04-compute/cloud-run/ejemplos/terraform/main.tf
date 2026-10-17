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

variable "imagen" {
  type = string
}

variable "subred" {
  type = string
}

variable "sa_llamador" {
  type        = string
  description = "Cuenta del servicio que llama a pedidos"
}

resource "google_service_account" "pedidos" {
  account_id   = "run-pedidos"
  display_name = "Cloud Run pedidos"
}

resource "google_cloud_run_v2_service" "pedidos" {
  name                = "pedidos"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
  deletion_protection = true

  template {
    service_account                  = google_service_account.pedidos.email
    max_instance_request_concurrency = 40

    scaling {
      min_instance_count = 2
      max_instance_count = 40
    }

    vpc_access {
      egress = "PRIVATE_RANGES_ONLY"
      network_interfaces {
        subnetwork = var.subred
      }
    }

    containers {
      image = var.imagen
      resources {
        limits = {
          cpu    = "1"
          memory = "1Gi"
        }
        startup_cpu_boost = true
      }
      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = "db-pedidos-password"
            version = "latest"
          }
        }
      }
      startup_probe {
        http_get {
          path = "/actuator/health/readiness"
        }
        period_seconds    = 2
        failure_threshold = 30
      }
    }
  }

  labels = {
    centro_costo = "tienda"
  }
}

resource "google_cloud_run_v2_service_iam_member" "llamador" {
  name     = google_cloud_run_v2_service.pedidos.name
  location = var.region
  role     = "roles/run.invoker"
  member   = "serviceAccount:${var.sa_llamador}"
}
