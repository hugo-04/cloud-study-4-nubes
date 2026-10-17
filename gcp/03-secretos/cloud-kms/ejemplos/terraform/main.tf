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
  project = var.proyecto_llaves
}

variable "proyecto_llaves" {
  type        = string
  description = "Proyecto dedicado a llaves"
}

variable "proyecto_datos" {
  type = string
}

variable "ubicacion" {
  type    = string
  default = "southamerica-west1"
}

variable "sa_app" {
  type = string
}

data "google_project" "datos" {
  project_id = var.proyecto_datos
}

resource "google_kms_key_ring" "tienda" {
  name     = "tienda"
  location = var.ubicacion
}

resource "google_kms_crypto_key" "datos_clientes" {
  name            = "datos-clientes"
  key_ring        = google_kms_key_ring.tienda.id
  purpose         = "ENCRYPT_DECRYPT"
  rotation_period = "7776000s"

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "HSM"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# La app usa la llave (cifrado de sobre)
resource "google_kms_crypto_key_iam_member" "app" {
  crypto_key_id = google_kms_crypto_key.datos_clientes.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${var.sa_app}"
}

# CMEK: el agente de Cloud Storage del proyecto de datos usa la llave
resource "google_kms_crypto_key_iam_member" "cmek_storage" {
  crypto_key_id = google_kms_crypto_key.datos_clientes.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.datos.number}@gs-project-accounts.iam.gserviceaccount.com"
}

resource "google_storage_bucket" "documentos" {
  project                     = var.proyecto_datos
  name                        = "${var.proyecto_datos}-documentos"
  location                    = upper(var.ubicacion)
  uniform_bucket_level_access = true

  encryption {
    default_kms_key_name = google_kms_crypto_key.datos_clientes.id
  }

  depends_on = [google_kms_crypto_key_iam_member.cmek_storage]
}
