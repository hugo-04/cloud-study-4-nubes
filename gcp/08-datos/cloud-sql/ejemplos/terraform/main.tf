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

variable "vpc" {
  type        = string
  description = "self_link de la VPC con PSA ya configurado"
}

resource "google_sql_database_instance" "pedidos" {
  name                = "pedidos-pg"
  database_version    = "POSTGRES_17"
  region              = var.region
  deletion_protection = true

  settings {
    tier              = "db-custom-2-7680"
    edition           = "ENTERPRISE"
    availability_type = "REGIONAL"

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.vpc
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
    }

    database_flags {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }

    maintenance_window {
      day  = 7
      hour = 4
    }

    insights_config {
      query_insights_enabled = true
    }
  }
}

resource "google_sql_database" "pedidos" {
  name     = "pedidos"
  instance = google_sql_database_instance.pedidos.name
}

resource "google_service_account" "app" {
  account_id   = "app-pedidos"
  display_name = "Servicio de pedidos"
}

# Usuario IAM: el email de la SA sin el sufijo .gserviceaccount.com
resource "google_sql_user" "app" {
  name     = trimsuffix(google_service_account.app.email, ".gserviceaccount.com")
  instance = google_sql_database_instance.pedidos.name
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
}

resource "google_project_iam_member" "app" {
  for_each = toset(["roles/cloudsql.client", "roles/cloudsql.instanceUser"])
  project  = var.proyecto
  role     = each.value
  member   = "serviceAccount:${google_service_account.app.email}"
}
