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

variable "emisor_oidc" {
  type        = string
  description = "URL del emisor OIDC de la plataforma de CI"
}

variable "repositorio" {
  type    = string
  default = "modalima/infra"
}

data "google_project" "actual" {}

resource "google_iam_workload_identity_pool" "ci_prod" {
  workload_identity_pool_id = "ci-prod"
  display_name              = "CI producción"
}

resource "google_iam_workload_identity_pool_provider" "ci" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.ci_prod.workload_identity_pool_id
  workload_identity_pool_provider_id = "plataforma-ci"
  display_name                       = "Plataforma de CI"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  # Solo la rama principal del repositorio de infraestructura
  attribute_condition = "assertion.repository == '${var.repositorio}' && assertion.ref == 'refs/heads/main'"

  oidc {
    issuer_uri = var.emisor_oidc
  }
}

resource "google_project_iam_member" "ci_despliega_run" {
  project = var.proyecto
  role    = "roles/run.developer"
  member  = "principalSet://iam.googleapis.com/projects/${data.google_project.actual.number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.ci_prod.workload_identity_pool_id}/attribute.repository/${var.repositorio}"
}
