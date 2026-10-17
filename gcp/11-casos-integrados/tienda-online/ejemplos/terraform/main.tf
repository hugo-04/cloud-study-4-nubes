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

variable "url_facturacion" {
  type    = string
  default = "https://facturacion-abc123-tl.a.run.app/eventos"
}

data "google_project" "actual" {}

resource "google_service_account" "pedidos" {
  account_id = "run-pedidos"
}

resource "google_service_account" "push" {
  account_id = "pubsub-push"
}

resource "google_pubsub_topic" "pedido_pagado" {
  name                       = "pedido-pagado"
  message_retention_duration = "604800s"
}

resource "google_pubsub_topic" "dlq" {
  name = "pedido-pagado-dlq"
}

resource "google_pubsub_topic_iam_member" "publica" {
  topic  = google_pubsub_topic.pedido_pagado.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${google_service_account.pedidos.email}"
}

resource "google_pubsub_subscription" "consumidores" {
  for_each                = toset(["facturacion", "despacho", "correos"])
  name                    = each.value
  topic                   = google_pubsub_topic.pedido_pagado.id
  ack_deadline_seconds    = 60
  enable_message_ordering = true

  dynamic "push_config" {
    for_each = each.value == "facturacion" ? [1] : []
    content {
      push_endpoint = var.url_facturacion
      oidc_token {
        service_account_email = google_service_account.push.email
      }
    }
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dlq.id
    max_delivery_attempts = 10
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
}

# El agente de Pub/Sub publica en la DLQ y confirma en la suscripción original
locals {
  agente = "serviceAccount:service-${data.google_project.actual.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_pubsub_topic_iam_member" "dlq" {
  topic  = google_pubsub_topic.dlq.name
  role   = "roles/pubsub.publisher"
  member = local.agente
}

resource "google_pubsub_subscription_iam_member" "dlq" {
  for_each     = google_pubsub_subscription.consumidores
  subscription = each.value.name
  role         = "roles/pubsub.subscriber"
  member       = local.agente
}

resource "google_cloud_run_v2_service_iam_member" "push_invoca" {
  name     = "facturacion"
  location = var.region
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.push.email}"
}
