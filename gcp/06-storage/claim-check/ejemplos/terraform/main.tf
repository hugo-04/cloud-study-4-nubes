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

resource "google_storage_bucket" "cargas" {
  name                        = "${var.proyecto}-cargas"
  location                    = "SOUTHAMERICA-WEST1"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  lifecycle_rule {
    condition {
      age = 7
    }
    action {
      type = "Delete"
    }
  }
}

resource "google_pubsub_topic" "mayoristas" {
  name                       = "pedidos-mayoristas"
  message_retention_duration = "345600s"
}

resource "google_pubsub_topic" "mayoristas_dlq" {
  name = "pedidos-mayoristas-dlq"
}

resource "google_pubsub_subscription" "facturacion" {
  name                       = "facturacion-mayoristas"
  topic                      = google_pubsub_topic.mayoristas.id
  ack_deadline_seconds       = 120
  message_retention_duration = "345600s" # 4 días < 7 días de la carga

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.mayoristas_dlq.id
    max_delivery_attempts = 5
  }
}
