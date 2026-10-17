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

variable "bucket_codigo" {
  type = string
}

variable "objeto_codigo" {
  type        = string
  description = "ZIP con el código de la función"
}

variable "tema" {
  type        = string
  description = "projects/<p>/topics/fotos-subidas"
}

resource "google_service_account" "funcion" {
  account_id   = "fn-miniaturas"
  display_name = "Función miniaturas"
}

resource "google_service_account" "disparador" {
  account_id   = "eventarc-miniaturas"
  display_name = "Disparador de miniaturas"
}

resource "google_cloudfunctions2_function" "miniaturas" {
  name     = "miniaturas"
  location = var.region

  build_config {
    runtime     = "java21"
    entry_point = "com.modalima.funciones.MiniaturaFuncion"
    source {
      storage_source {
        bucket = var.bucket_codigo
        object = var.objeto_codigo
      }
    }
  }

  service_config {
    available_memory      = "512Mi"
    timeout_seconds       = 120
    max_instance_count    = 20
    min_instance_count    = 0
    ingress_settings      = "ALLOW_INTERNAL_ONLY"
    service_account_email = google_service_account.funcion.email
  }

  event_trigger {
    trigger_region        = var.region
    event_type            = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic          = var.tema
    retry_policy          = "RETRY_POLICY_RETRY"
    service_account_email = google_service_account.disparador.email
  }
}

resource "google_cloud_run_service_iam_member" "disparador_invoca" {
  location = var.region
  service  = google_cloudfunctions2_function.miniaturas.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.disparador.email}"
}
