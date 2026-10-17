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

variable "subred_privada_id" {
  type = string
}

variable "admin_password" {
  type        = string
  sensitive   = true
  description = "Pásala desde Vault en el pipeline; nunca en un .tfvars del repo"
}

resource "oci_mysql_mysql_db_system" "catalogo" {
  compartment_id          = var.compartimento_id
  availability_domain     = var.dominio_disponibilidad
  display_name            = "mysql-catalogo"
  shape_name              = "MySQL.4"
  subnet_id               = var.subred_privada_id
  admin_username          = "administrador"
  admin_password          = var.admin_password
  data_storage_size_in_gb = 100
  is_highly_available     = true
  hostname_label          = "catalogo"

  backup_policy {
    is_enabled        = true
    retention_in_days = 14
    window_start_time = "06:00"
    pitr_policy {
      is_enabled = true
    }
  }

  deletion_policy {
    automatic_backup_retention = "RETAIN"
    final_backup               = "REQUIRE_FINAL_BACKUP"
    is_delete_protected        = true
  }
}

resource "oci_mysql_heat_wave_cluster" "catalogo" {
  db_system_id = oci_mysql_mysql_db_system.catalogo.id
  shape_name   = "HeatWave.512GB"
  cluster_size = 2
}

output "ip_primaria" {
  value = oci_mysql_mysql_db_system.catalogo.ip_address
}
