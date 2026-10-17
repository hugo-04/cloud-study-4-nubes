terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
  }
}

variable "nombre" {
  type = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,24}$", var.nombre))
    error_message = "nombre: minúsculas, números y guiones, 3-25 caracteres."
  }
}

variable "imagen" {
  type = string
  validation {
    condition     = can(regex("@sha256:", var.imagen))
    error_message = "La imagen debe ir por digest (@sha256:...)."
  }
}

variable "entorno" {
  type = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.entorno)
    error_message = "entorno: dev, staging o prod."
  }
}

variable "region" {
  type    = string
  default = "southamerica-west1"
}

variable "equipo" {
  type = string
}

variable "min_instancias" {
  type    = number
  default = 0
}

variable "max_instancias" {
  type    = number
  default = 3
}

variable "secretos" {
  type        = map(string)
  default     = {}
  description = "VARIABLE => id del secreto"
}

variable "invocadores" {
  type    = list(string)
  default = []
}

resource "google_service_account" "app" {
  account_id   = "run-${var.nombre}"
  display_name = "Cloud Run ${var.nombre} (${var.entorno})"
}

resource "google_secret_manager_secret_iam_member" "lee" {
  for_each  = var.secretos
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.app.email}"
}

resource "google_cloud_run_v2_service" "app" {
  name                = var.nombre
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
  deletion_protection = var.entorno == "prod"

  labels = {
    equipo  = var.equipo
    entorno = var.entorno
    modulo  = "microservicio"
  }

  template {
    service_account = google_service_account.app.email

    scaling {
      min_instance_count = var.min_instancias
      max_instance_count = var.max_instancias
    }

    containers {
      image = var.imagen

      dynamic "env" {
        for_each = var.secretos
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value
              version = "latest"
            }
          }
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = var.entorno != "prod" || var.min_instancias >= 1
      error_message = "En prod min_instancias debe ser >= 1."
    }
    precondition {
      condition     = var.max_instancias >= var.min_instancias
      error_message = "max_instancias < min_instancias."
    }
  }

  depends_on = [google_secret_manager_secret_iam_member.lee]
}

resource "google_cloud_run_v2_service_iam_member" "invocador" {
  for_each = toset(var.invocadores)
  name     = google_cloud_run_v2_service.app.name
  location = var.region
  role     = "roles/run.invoker"
  member   = each.value
}

output "url" {
  value = google_cloud_run_v2_service.app.uri
}

output "cuenta" {
  value = google_service_account.app.email
}
