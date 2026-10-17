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

variable "subred" {
  type        = string
  description = "projects/<p>/regions/<r>/subnetworks/<s> donde viven los clientes"
}

resource "google_managed_kafka_cluster" "eventos" {
  cluster_id = "eventos-modalima"
  location   = var.region

  capacity_config {
    vcpu_count   = 3
    memory_bytes = 3221225472
  }

  gcp_config {
    access_config {
      network_configs {
        subnet = var.subred
      }
    }
  }

  labels = {
    equipo = "plataforma"
  }
}

resource "google_managed_kafka_topic" "clickstream" {
  topic_id           = "clickstream"
  cluster            = google_managed_kafka_cluster.eventos.cluster_id
  location           = var.region
  partition_count    = 12
  replication_factor = 3

  configs = {
    "retention.ms"   = "604800000"
    "cleanup.policy" = "delete"
  }
}

resource "google_service_account" "app" {
  account_id   = "clickstream-app"
  display_name = "Productor y consumidor de clickstream"
}

resource "google_project_iam_member" "cliente" {
  project = var.proyecto
  role    = "roles/managedkafka.client"
  member  = "serviceAccount:${google_service_account.app.email}"
}
