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
  type        = string
  description = "Proyecto host de la red"
}

variable "region" {
  type    = string
  default = "southamerica-west1"
}

resource "google_compute_network" "vpc" {
  name                    = "modalima-vpc"
  auto_create_subnetworks = false
  routing_mode            = "GLOBAL"
}

resource "google_compute_subnetwork" "apps" {
  name                     = "apps"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = "10.10.0.0/20"
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.20.0.0/16"
  }

  secondary_ip_range {
    range_name    = "servicios"
    ip_cidr_range = "10.30.0.0/20"
  }

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_subnetwork" "datos" {
  name                     = "datos"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = "10.10.16.0/22"
  private_ip_google_access = true

  log_config {
    flow_sampling = 0.5
  }
}

# Shared VPC: este proyecto es host
resource "google_compute_shared_vpc_host_project" "host" {
  project = var.proyecto
}
