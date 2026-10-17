terraform {
  required_version = ">= 1.5"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 7.0"
    }
  }
}

provider "oci" {
  region = var.region
}

variable "region" {
  type    = string
  default = "sa-saopaulo-1"
}

variable "compartimento_id" {
  type = string
}

variable "dominio_disponibilidad" {
  type = string
}

variable "subred_id" {
  type = string
}

variable "nsg_mount_target_id" {
  type = string
}

variable "cidr_apps" {
  type    = string
  default = "10.0.2.0/24"
}

variable "cidr_reportes" {
  type    = string
  default = "10.0.5.0/24"
}

resource "oci_file_storage_filesystem_snapshot_policy" "diaria" {
  compartment_id      = var.compartimento_id
  availability_domain = var.dominio_disponibilidad
  display_name        = "snap-diaria-30d"
  policy_prefix       = "diaria"

  schedules {
    period                        = "DAILY"
    time_zone                     = "UTC"
    hour_of_day                   = 6
    retention_duration_in_seconds = 2592000
    schedule_prefix               = "d"
  }
}

resource "oci_file_storage_file_system" "media" {
  compartment_id                = var.compartimento_id
  availability_domain           = var.dominio_disponibilidad
  display_name                  = "fs-catalogo-media"
  filesystem_snapshot_policy_id = oci_file_storage_filesystem_snapshot_policy.diaria.id
}

resource "oci_file_storage_mount_target" "media" {
  compartment_id      = var.compartimento_id
  availability_domain = var.dominio_disponibilidad
  subnet_id           = var.subred_id
  display_name        = "mt-media"
  nsg_ids             = [var.nsg_mount_target_id]
}

resource "oci_file_storage_export" "media" {
  export_set_id  = oci_file_storage_mount_target.media.export_set_id
  file_system_id = oci_file_storage_file_system.media.id
  path           = "/catalogo-media"

  export_options {
    source                         = var.cidr_apps
    access                         = "READ_WRITE"
    identity_squash                = "ROOT"
    require_privileged_source_port = true
  }

  export_options {
    source                         = var.cidr_reportes
    access                         = "READ_ONLY"
    identity_squash                = "ALL"
    require_privileged_source_port = true
  }
}

output "ip_mount_target" {
  value = oci_file_storage_mount_target.media.ip_address
}
