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
  description = "projects/<p>/global/networks/<red> (con la política de conexión de servicio de PSC)"
}

resource "google_memorystore_instance" "cache" {
  instance_id                 = "cache-tienda"
  location                    = var.region
  shard_count                 = 1
  replica_count               = 1
  node_type                   = "SHARED_CORE_NANO"
  mode                        = "CLUSTER_DISABLED"
  transit_encryption_mode     = "SERVER_AUTHENTICATION"
  authorization_mode          = "IAM_AUTH"
  deletion_protection_enabled = true

  desired_auto_created_endpoints {
    network    = var.vpc
    project_id = var.proyecto
  }

  engine_configs = {
    "maxmemory-policy" = "allkeys-lru"
  }

  zone_distribution_config {
    mode = "MULTI_ZONE"
  }
}
