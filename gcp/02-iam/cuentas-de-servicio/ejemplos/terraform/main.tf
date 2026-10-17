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

variable "sa_pipeline" {
  type        = string
  description = "Cuenta del pipeline que despliega"
}

resource "google_service_account" "pedidos" {
  account_id   = "pedidos"
  display_name = "Servicio de pedidos"
}

# Roles mínimos de datos
resource "google_project_iam_member" "pedidos_pubsub" {
  project = var.proyecto
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.pedidos.email}"
}

resource "google_project_iam_member" "pedidos_secretos" {
  project = var.proyecto
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.pedidos.email}"
}

# Solo el pipeline puede desplegar servicios que actúen como "pedidos"
resource "google_service_account_iam_member" "pipeline_actua_como" {
  service_account_id = google_service_account.pedidos.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${var.sa_pipeline}"
}

# La guardia puede suplantar para diagnosticar (auditado)
resource "google_service_account_iam_member" "guardia_suplanta" {
  service_account_id = google_service_account.pedidos.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "group:guardia@modalima.example"
}
