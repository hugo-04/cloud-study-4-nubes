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

variable "nsg_db_id" {
  type        = string
  description = "NSG: 1522/TCP solo desde las subredes de apps"
}

variable "secreto_admin_id" {
  type        = string
  description = "Secreto de Vault con la contraseña de ADMIN"
}

resource "oci_database_autonomous_database" "pedidos" {
  compartment_id              = var.compartimento_id
  display_name                = "atp-pedidos"
  db_name                     = "PEDIDOS"
  db_workload                 = "OLTP"
  compute_model               = "ECPU"
  compute_count               = 2
  is_auto_scaling_enabled     = true
  data_storage_size_in_tbs    = 1
  secret_id                   = var.secreto_admin_id
  subnet_id                   = var.subred_privada_id
  nsg_ids                     = [var.nsg_db_id]
  is_mtls_connection_required = false
  is_local_data_guard_enabled = true
  license_model               = "LICENSE_INCLUDED"

  freeform_tags = {
    proyecto = "modalima"
    datos    = "personales"
  }

  lifecycle {
    prevent_destroy = true
  }
}

output "perfiles" {
  value = [for p in oci_database_autonomous_database.pedidos.connection_strings[0].profiles : p.display_name if p.tls_authentication == "SERVER"]
}
