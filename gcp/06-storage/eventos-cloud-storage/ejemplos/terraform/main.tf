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

variable "bucket_fotos" {
  type = string
}

variable "url_miniaturas" {
  type        = string
  description = "URL del Cloud Run que recibe el push"
}

variable "sa_push" {
  type        = string
  description = "Cuenta con run.invoker con la que firma el push"
}

data "google_storage_project_service_account" "agente" {}

resource "google_pubsub_topic" "fotos" {
  name = "fotos-subidas"
}

resource "google_pubsub_topic" "fotos_dlq" {
  name = "fotos-subidas-dlq"
}

resource "google_pubsub_topic_iam_member" "agente_publica" {
  topic  = google_pubsub_topic.fotos.id
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${data.google_storage_project_service_account.agente.email_address}"
}

resource "google_storage_notification" "fotos" {
  bucket             = var.bucket_fotos
  topic              = google_pubsub_topic.fotos.id
  payload_format     = "JSON_API_V1"
  event_types        = ["OBJECT_FINALIZE"]
  object_name_prefix = "fotos/"
  depends_on         = [google_pubsub_topic_iam_member.agente_publica]
}

resource "google_pubsub_subscription" "miniaturas" {
  name                 = "miniaturas"
  topic                = google_pubsub_topic.fotos.id
  ack_deadline_seconds = 60

  push_config {
    push_endpoint = "${var.url_miniaturas}/push"
    oidc_token {
      service_account_email = var.sa_push
    }
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.fotos_dlq.id
    max_delivery_attempts = 5
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "300s"
  }
}
