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
  project = var.proyecto_ci
}

variable "proyecto_ci" {
  type    = string
  default = "modalima-ci"
}

variable "emisor" {
  type    = string
  default = "https://ci.modalima.example"
}

variable "repositorio" {
  type    = string
  default = "modalima/infra"
}

variable "entornos" {
  type = map(string)
  default = {
    dev  = "modalima-tienda-dev"
    prod = "modalima-tienda-prod"
  }
}

resource "google_iam_workload_identity_pool" "ci" {
  workload_identity_pool_id = "ci-modalima"
  display_name              = "CI de ModaLima"
}

resource "google_iam_workload_identity_pool_provider" "ci" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.ci.workload_identity_pool_id
  workload_identity_pool_provider_id = "plataforma-ci"
  attribute_mapping = {
    "google.subject"        = "assertion.sub"
    "attribute.repository"  = "assertion.repository"
    "attribute.ref"         = "assertion.ref"
    "attribute.environment" = "assertion.environment"
  }
  attribute_condition = "assertion.repository == '${var.repositorio}'"

  oidc {
    issuer_uri = var.emisor
  }
}

resource "google_service_account" "plan" {
  for_each   = var.entornos
  account_id = "tf-plan-${each.key}"
}

resource "google_service_account" "apply" {
  for_each   = var.entornos
  account_id = "tf-apply-${each.key}"
}

locals {
  repo_principal = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.ci.name}/attribute.repository/${var.repositorio}"
}

# Cualquier rama del repo puede planificar
resource "google_service_account_iam_member" "plan" {
  for_each           = var.entornos
  service_account_id = google_service_account.plan[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.repo_principal
}

# Solo el entorno protegido del CI (main + aprobación) puede aplicar
resource "google_service_account_iam_member" "apply" {
  for_each           = var.entornos
  service_account_id = google_service_account.apply[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.ci.name}/attribute.environment/${each.key}"
}

resource "google_project_iam_member" "plan_lee" {
  for_each = { for p in setproduct(keys(var.entornos), ["roles/viewer", "roles/iam.securityReviewer"]) : "${p[0]}-${p[1]}" => p }
  project  = var.entornos[each.value[0]]
  role     = each.value[1]
  member   = "serviceAccount:${google_service_account.plan[each.value[0]].email}"
}

resource "google_project_iam_member" "apply_escribe" {
  for_each = var.entornos
  project  = each.value
  role     = "roles/editor" # en la práctica: roles concretos por componente
  member   = "serviceAccount:${google_service_account.apply[each.key].email}"
}
