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

variable "sa_productor" {
  type = string
}

variable "servicio_destino" {
  type    = string
  default = "correos"
}

resource "google_service_account" "despacho" {
  account_id   = "tasks-despacho"
  display_name = "Cloud Tasks: despacho de recordatorios"
}

resource "google_cloud_tasks_queue" "recordatorios" {
  name     = "recordatorios"
  location = var.region

  rate_limits {
    max_dispatches_per_second = 50
    max_concurrent_dispatches = 20
  }

  retry_config {
    max_attempts       = 10
    max_retry_duration = "86400s"
    min_backoff        = "10s"
    max_backoff        = "300s"
    max_doublings      = 5
  }
}

resource "google_cloud_tasks_queue_iam_member" "productor" {
  name     = google_cloud_tasks_queue.recordatorios.name
  location = var.region
  role     = "roles/cloudtasks.enqueuer"
  member   = "serviceAccount:${var.sa_productor}"
}

# El productor crea tareas que se despachan como la SA de despacho
resource "google_service_account_iam_member" "productor_actua_como" {
  service_account_id = google_service_account.despacho.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${var.sa_productor}"
}

resource "google_cloud_run_v2_service_iam_member" "despacho_invoca" {
  name     = var.servicio_destino
  location = var.region
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.despacho.email}"
}
