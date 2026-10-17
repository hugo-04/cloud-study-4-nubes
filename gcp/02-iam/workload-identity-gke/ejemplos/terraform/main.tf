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

variable "red" {
  type = string
}

variable "subred" {
  type = string
}

data "google_project" "actual" {}

resource "google_container_cluster" "tienda" {
  name                     = "tienda"
  location                 = var.region
  network                  = var.red
  subnetwork               = var.subred
  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = true

  workload_identity_config {
    workload_pool = "${var.proyecto}.svc.id.goog"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "servicios"
  }
}

resource "google_container_node_pool" "general" {
  name       = "general"
  cluster    = google_container_cluster.tienda.id
  node_count = 2

  node_config {
    machine_type = "e2-standard-4"
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }
}

# Rol directo a la KSA tienda/pedidos (sin cuenta de servicio de IAM)
resource "google_project_iam_member" "pedidos_publica" {
  project = var.proyecto
  role    = "roles/pubsub.publisher"
  member  = "principal://iam.googleapis.com/projects/${data.google_project.actual.number}/locations/global/workloadIdentityPools/${var.proyecto}.svc.id.goog/subject/ns/tienda/sa/pedidos"
}
