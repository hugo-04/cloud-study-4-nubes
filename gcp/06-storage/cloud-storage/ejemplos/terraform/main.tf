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

variable "llave_kms" {
  type = string
}

variable "sa_pedidos" {
  type = string
}

resource "google_storage_bucket" "comprobantes" {
  name                        = "${var.proyecto}-comprobantes"
  location                    = "SOUTHAMERICA-WEST1"
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  encryption {
    default_kms_key_name = var.llave_kms
  }

  lifecycle_rule {
    condition {
      age            = 90
      matches_prefix = ["pedidos/"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 3
    }
    action {
      type = "Delete"
    }
  }

  labels = {
    centro_costo = "tienda"
    datos        = "personales"
  }
}

resource "google_storage_bucket_iam_member" "pedidos_escribe" {
  bucket = google_storage_bucket.comprobantes.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${var.sa_pedidos}"
}
