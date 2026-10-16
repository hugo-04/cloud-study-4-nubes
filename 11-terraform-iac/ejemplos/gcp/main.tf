# Laboratorio GCP: VPC privada + Cloud NAT + bucket sin acceso publico.
# Material de estudio. Ejecuta: terraform init && terraform plan
# Requiere un proyecto existente y credenciales: gcloud auth application-default login
# Al terminar: terraform destroy

terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

variable "proyecto" {
  type        = string
  description = "ID del proyecto de GCP"
}

variable "region" {
  type    = string
  default = "us-central1"
}

provider "google" {
  project = var.proyecto
  region  = var.region
}

resource "random_id" "sufijo" {
  byte_length = 4
}

resource "google_compute_network" "vpc" {
  name                    = "vpc-estudio"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "app" {
  name                     = "snet-app"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = "10.40.1.0/24"
  private_ip_google_access = true # llega a las APIs de Google (Storage) sin IP externa
}

# El trafico de entrada esta negado por defecto; este permiso es minimo y por etiqueta.
resource "google_compute_firewall" "https_desde_web" {
  name      = "allow-https-from-web"
  network   = google_compute_network.vpc.name
  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  source_ranges = ["10.40.0.0/24"]
  target_tags   = ["app"]
}

# Salida controlada a internet: Cloud NAT (las VM no necesitan IP externa).
resource "google_compute_router" "router" {
  name    = "router-estudio"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "nat-estudio"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "google_storage_bucket" "datos" {
  name     = "modalima-estudio-${random_id.sufijo.hex}"
  location = "US-CENTRAL1"

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }
}

output "nombre_bucket" {
  value = google_storage_bucket.datos.name
}

output "subnet_app_id" {
  value = google_compute_subnetwork.app.id
}
