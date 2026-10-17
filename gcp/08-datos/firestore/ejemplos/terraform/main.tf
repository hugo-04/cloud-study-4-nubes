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

resource "google_firestore_database" "tienda" {
  name                              = "tienda"
  location_id                       = "southamerica-east1"
  type                              = "FIRESTORE_NATIVE"
  delete_protection_state           = "DELETE_PROTECTION_ENABLED"
  point_in_time_recovery_enablement = "POINT_IN_TIME_RECOVERY_ENABLED"
}

resource "google_firestore_index" "carritos_por_nivel" {
  database    = google_firestore_database.tienda.name
  collection  = "carritos"
  query_scope = "COLLECTION_GROUP"

  fields {
    field_path = "nivel"
    order      = "ASCENDING"
  }

  fields {
    field_path = "actualizado"
    order      = "DESCENDING"
  }
}

resource "google_firestore_field" "ttl_carritos" {
  database   = google_firestore_database.tienda.name
  collection = "carritos"
  field      = "expira"

  ttl_config {}
}

resource "google_service_account" "app" {
  account_id   = "app-carritos"
  display_name = "Carritos"
}

resource "google_project_iam_member" "app" {
  project = var.proyecto
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.app.email}"
}
