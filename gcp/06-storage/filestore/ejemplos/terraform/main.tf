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

variable "zona" {
  type    = string
  default = "southamerica-west1-a"
}

variable "red" {
  type = string
}

resource "google_filestore_instance" "media" {
  name     = "media"
  location = var.zona
  tier     = "ZONAL"

  file_shares {
    name        = "catalogo"
    capacity_gb = 1024

    nfs_export_options {
      ip_ranges   = ["10.10.0.0/20"]
      access_mode = "READ_WRITE"
      squash_mode = "ROOT_SQUASH"
      anon_uid    = 65534
      anon_gid    = 65534
    }

    nfs_export_options {
      ip_ranges   = ["10.10.16.0/22"]
      access_mode = "READ_ONLY"
      squash_mode = "ROOT_SQUASH"
      anon_uid    = 65534
      anon_gid    = 65534
    }
  }

  networks {
    network      = var.red
    modes        = ["MODE_IPV4"]
    connect_mode = "PRIVATE_SERVICE_ACCESS"
  }

  labels = {
    centro_costo = "tienda"
  }
}
