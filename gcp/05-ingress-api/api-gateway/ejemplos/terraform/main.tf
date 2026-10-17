terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 8.0"
    }
  }
}

provider "google" {
  project = var.proyecto
  region  = var.region
}

# Los recursos de API Gateway están en el proveedor beta (verifica)
provider "google-beta" {
  project = var.proyecto
  region  = var.region
}

variable "proyecto" {
  type = string
}

variable "region" {
  type    = string
  default = "us-central1" # regiones disponibles para API Gateway: verifica
}

variable "servicio_backend" {
  type    = string
  default = "pedidos"
}

variable "region_backend" {
  type    = string
  default = "southamerica-west1"
}

resource "google_service_account" "gateway" {
  account_id   = "api-gateway-tienda"
  display_name = "Cuenta con la que el gateway llama a los backends"
}

resource "google_cloud_run_v2_service_iam_member" "gateway_invoca" {
  name     = var.servicio_backend
  location = var.region_backend
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.gateway.email}"
}

resource "google_api_gateway_api" "tienda" {
  provider = google-beta
  api_id   = "tienda"
}

resource "google_api_gateway_api_config" "v1" {
  provider             = google-beta
  api                  = google_api_gateway_api.tienda.api_id
  api_config_id_prefix = "tienda-v1-"

  openapi_documents {
    document {
      path     = "tienda.yaml"
      contents = filebase64("${path.module}/../openapi/tienda.yaml")
    }
  }

  gateway_config {
    backend_config {
      google_service_account = google_service_account.gateway.email
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_api_gateway_gateway" "tienda" {
  provider   = google-beta
  gateway_id = "tienda-gw"
  api_config = google_api_gateway_api_config.v1.id
  region     = var.region
}
