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

resource "google_bigtable_instance" "telemetria" {
  name                = "telemetria-cafe"
  deletion_protection = true

  cluster {
    cluster_id   = "telemetria-a"
    zone         = "southamerica-east1-a"
    storage_type = "SSD"

    autoscaling_config {
      min_nodes  = 1
      max_nodes  = 5
      cpu_target = 70
    }
  }

  labels = {
    equipo = "iot"
  }
}

resource "google_bigtable_table" "lecturas" {
  name          = "lecturas"
  instance_name = google_bigtable_instance.telemetria.name

  column_family {
    family = "m"
  }
}

resource "google_bigtable_gc_policy" "m_30_dias" {
  instance_name   = google_bigtable_instance.telemetria.name
  table           = google_bigtable_table.lecturas.name
  column_family   = "m"
  deletion_policy = "ABANDON"

  max_age {
    duration = "720h"
  }
}

resource "google_service_account" "app" {
  account_id   = "app-telemetria"
  display_name = "Ingesta de telemetría"
}

resource "google_bigtable_instance_iam_member" "app" {
  instance = google_bigtable_instance.telemetria.name
  role     = "roles/bigtable.user"
  member   = "serviceAccount:${google_service_account.app.email}"
}
