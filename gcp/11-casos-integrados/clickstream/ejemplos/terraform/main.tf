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

variable "cluster" {
  type    = string
  default = "eventos-modalima"
}

resource "google_managed_kafka_topic" "clickstream" {
  topic_id           = "clickstream"
  cluster            = var.cluster
  location           = var.region
  partition_count    = 12
  replication_factor = 3

  configs = {
    "retention.ms" = "604800000"
  }
}

resource "google_service_account" "colector" {
  account_id = "run-colector"
}

resource "google_service_account" "tablero" {
  account_id = "gke-tablero"
}

resource "google_project_iam_member" "kafka" {
  for_each = {
    colector = google_service_account.colector.email
    tablero  = google_service_account.tablero.email
  }
  project = var.proyecto
  role    = "roles/managedkafka.client"
  member  = "serviceAccount:${each.value}"
}

# Pod del tablero en GKE con Workload Identity (namespace clickstream, KSA tablero)
resource "google_service_account_iam_member" "wi_tablero" {
  service_account_id = google_service_account.tablero.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.proyecto}.svc.id.goog[clickstream/tablero]"
}

resource "google_bigquery_dataset" "historial" {
  dataset_id                  = "clickstream"
  location                    = "southamerica-west1"
  default_table_expiration_ms = 31536000000
}
