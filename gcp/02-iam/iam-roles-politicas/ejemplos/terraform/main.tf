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

variable "fin_acceso_soporte" {
  type        = string
  description = "RFC3339, por ejemplo 2026-10-31T00:00:00Z"
}

# Aditivo: no toca otros miembros del rol
resource "google_project_iam_member" "devs_run" {
  project = var.proyecto
  role    = "roles/run.developer"
  member  = "group:tienda-devs@modalima.example"
}

resource "google_project_iam_custom_role" "soporte" {
  project     = var.proyecto
  role_id     = "soporteTienda"
  title       = "Soporte de la tienda"
  description = "Ver servicios y registros, sin cambiar nada"
  permissions = [
    "run.services.get",
    "run.services.list",
    "logging.logEntries.list",
  ]
}

# Acceso temporal que vence solo
resource "google_project_iam_member" "proveedor_temporal" {
  project = var.proyecto
  role    = google_project_iam_custom_role.soporte.id
  member  = "group:proveedor-soporte@modalima.example"

  condition {
    title       = "vence"
    description = "Acceso de soporte acotado en el tiempo"
    expression  = "request.time < timestamp(\"${var.fin_acceso_soporte}\")"
  }
}
