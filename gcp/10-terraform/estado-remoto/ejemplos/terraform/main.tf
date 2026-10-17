# Bootstrap: el bucket del estado (este archivo usa estado local o el de un bootstrap aparte)
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
  type    = string
  default = "modalima-tfstate"
}

variable "entorno" {
  type    = string
  default = "prod"
}

resource "google_kms_key_ring" "estado" {
  name     = "tfstate"
  location = "southamerica-west1"
}

resource "google_kms_crypto_key" "estado" {
  name            = "tfstate-${var.entorno}"
  key_ring        = google_kms_key_ring.estado.id
  rotation_period = "7776000s"

  lifecycle {
    prevent_destroy = true
  }
}

data "google_storage_project_service_account" "gcs" {}

resource "google_kms_crypto_key_iam_member" "gcs" {
  crypto_key_id = google_kms_crypto_key.estado.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${data.google_storage_project_service_account.gcs.email_address}"
}

resource "google_storage_bucket" "estado" {
  name                        = "modalima-tfstate-${var.entorno}"
  location                    = "SOUTHAMERICA-WEST1"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  encryption {
    default_kms_key_name = google_kms_crypto_key.estado.id
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 30
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [google_kms_crypto_key_iam_member.gcs]
}

resource "google_service_account" "tf" {
  account_id   = "tf-${var.entorno}"
  display_name = "Terraform ${var.entorno}"
}

resource "google_storage_bucket_iam_member" "tf" {
  bucket = google_storage_bucket.estado.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.tf.email}"
}
