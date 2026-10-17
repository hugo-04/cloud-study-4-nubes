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

variable "sa_facturacion" {
  type = string
}

data "google_project" "actual" {}

locals {
  agente_pubsub = "serviceAccount:service-${data.google_project.actual.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_pubsub_topic" "pagados" {
  name                       = "pedidos-pagados"
  message_retention_duration = "604800s"
}

resource "google_pubsub_topic" "pagados_dlq" {
  name = "pedidos-pagados-dlq"
}

resource "google_pubsub_subscription" "facturacion" {
  name                    = "facturacion"
  topic                   = google_pubsub_topic.pagados.id
  ack_deadline_seconds    = 60
  enable_message_ordering = true

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.pagados_dlq.id
    max_delivery_attempts = 5
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
}

resource "google_pubsub_subscription_iam_member" "facturacion_consume" {
  subscription = google_pubsub_subscription.facturacion.name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${var.sa_facturacion}"
}

# La DLQ funciona con la identidad del agente de Pub/Sub
resource "google_pubsub_topic_iam_member" "agente_dlq" {
  topic  = google_pubsub_topic.pagados_dlq.id
  role   = "roles/pubsub.publisher"
  member = local.agente_pubsub
}

resource "google_pubsub_subscription_iam_member" "agente_origen" {
  subscription = google_pubsub_subscription.facturacion.name
  role         = "roles/pubsub.subscriber"
  member       = local.agente_pubsub
}
