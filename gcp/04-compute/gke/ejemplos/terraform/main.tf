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

variable "red" {
  type = string
}

variable "subred" {
  type = string
}

variable "red_admin" {
  type        = string
  description = "CIDR autorizado para el plano de control (bastión/VPN)"
  default     = "10.10.250.0/24"
}

resource "google_container_cluster" "tienda" {
  name                = "tienda"
  location            = var.region
  enable_autopilot    = true
  network             = var.red
  subnetwork          = var.subred
  deletion_protection = true

  release_channel {
    channel = "REGULAR"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "servicios"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = var.red_admin
      display_name = "administracion"
    }
  }

  maintenance_policy {
    recurring_window {
      start_time = "2026-01-01T06:00:00Z"
      end_time   = "2026-01-01T10:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=TU,WE,TH"
    }
  }

  resource_labels = {
    centro_costo = "tienda"
  }
}
