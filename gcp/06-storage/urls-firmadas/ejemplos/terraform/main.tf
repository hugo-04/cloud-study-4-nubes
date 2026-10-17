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

variable "sa_backend" {
  type        = string
  description = "Cuenta que firma URLs (la del servicio)"
}

variable "origen_web" {
  type    = string
  default = "https://www.modalima.example"
}

resource "google_storage_bucket" "fotos" {
  name                        = "${var.proyecto}-fotos"
  location                    = "SOUTHAMERICA-WEST1"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  cors {
    origin          = [var.origen_web]
    method          = ["PUT", "GET"]
    response_header = ["Content-Type", "x-goog-if-generation-match"]
    max_age_seconds = 600
  }
}

# El firmante solo puede crear objetos (las URLs PUT heredan este permiso)
resource "google_storage_bucket_iam_member" "backend_crea" {
  bucket = google_storage_bucket.fotos.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${var.sa_backend}"
}

# Firmar sin llaves: la cuenta puede usar signBlob sobre sí misma
resource "google_service_account_iam_member" "firma_sin_llave" {
  service_account_id = "projects/${var.proyecto}/serviceAccounts/${var.sa_backend}"
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${var.sa_backend}"
}
