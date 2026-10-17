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

variable "canal_guardia" {
  type        = string
  description = "ID del canal de notificación de la guardia"
}

resource "google_monitoring_alert_policy" "tasa_5xx" {
  display_name = "Tienda: tasa de 5xx del LB > 2 %"
  combiner     = "OR"

  conditions {
    display_name = "5xx / total > 0.02 durante 5 min"
    # PromQL (recomendado sobre MQL; verifica nombres de métricas en tu proyecto)
    condition_prometheus_query_language {
      duration = "300s"
      query    = "sum(rate(loadbalancing_googleapis_com:https_request_count{monitored_resource=\"https_lb_rule\",response_code_class=\"500\"}[5m])) / sum(rate(loadbalancing_googleapis_com:https_request_count{monitored_resource=\"https_lb_rule\"}[5m])) > 0.02"
    }
  }

  notification_channels = [var.canal_guardia]

  documentation {
    content   = "Runbook: revisar capas en orden (borde, backends, cómputo, dependencias, cambios). Mitigar primero: revertir la revisión de Cloud Run."
    mime_type = "text/markdown"
  }
}

resource "google_service_account" "triage" {
  account_id = "triage-capas"
}

resource "google_project_iam_member" "triage" {
  project = var.proyecto
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.triage.email}"
}
