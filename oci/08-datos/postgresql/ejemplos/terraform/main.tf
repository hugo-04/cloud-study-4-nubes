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

variable "subred_privada_id" {
  type = string
}

variable "nsg_id" {
  type = string
}

variable "secreto_admin_id" {
  type        = string
  description = "Secreto de Vault con la contraseña del administrador"
}

resource "oci_psql_db_system" "pedidos" {
  compartment_id              = var.compartimento_id
  display_name                = "pg-pedidos"
  db_version                  = "16"
  shape                       = "PostgreSQL.VM.Standard.E5.Flex"
  instance_ocpu_count         = 2
  instance_memory_size_in_gbs = 32
  instance_count              = 2

  network_details {
    subnet_id                  = var.subred_privada_id
    nsg_ids                    = [var.nsg_id]
    is_reader_endpoint_enabled = true
  }

  storage_details {
    system_type           = "OCI_OPTIMIZED_STORAGE"
    is_regionally_durable = true
  }

  credentials {
    username = "administrador"
    password_details {
      password_type = "VAULT_SECRET"
      secret_id     = var.secreto_admin_id
    }
  }

  management_policy {
    maintenance_window_start = "SUN 06:00"
    backup_policy {
      kind           = "DAILY"
      backup_start   = "05:00"
      retention_days = 14
    }
  }
}
