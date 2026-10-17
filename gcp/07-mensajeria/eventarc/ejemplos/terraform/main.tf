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

variable "servicio_alertas" {
  type    = string
  default = "seguridad-alertas"
}

resource "google_service_account" "disparador" {
  account_id   = "eventarc-iam"
  display_name = "Disparador de cambios de IAM"
}

resource "google_project_iam_member" "receptor" {
  project = var.proyecto
  role    = "roles/eventarc.eventReceiver"
  member  = "serviceAccount:${google_service_account.disparador.email}"
}

resource "google_cloud_run_v2_service_iam_member" "invoca" {
  name     = var.servicio_alertas
  location = var.region
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.disparador.email}"
}

# Los eventos de Audit Logs se filtran por tipo + servicio + método
resource "google_eventarc_trigger" "iam_cambiado" {
  name            = "iam-cambiado"
  location        = "global"
  service_account = google_service_account.disparador.email

  matching_criteria {
    attribute = "type"
    value     = "google.cloud.audit.log.v1.written"
  }

  matching_criteria {
    attribute = "serviceName"
    value     = "cloudresourcemanager.googleapis.com"
  }

  matching_criteria {
    attribute = "methodName"
    value     = "SetIamPolicy"
  }

  destination {
    cloud_run_service {
      service = var.servicio_alertas
      region  = var.region
      path    = "/eventos/iam"
    }
  }
}
