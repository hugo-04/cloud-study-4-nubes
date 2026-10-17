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

resource "oci_nosql_table" "carritos" {
  compartment_id = var.compartimento_id
  name           = "carritos"
  ddl_statement  = "CREATE TABLE IF NOT EXISTS carritos (id_cliente STRING, id_carrito STRING, items JSON, total NUMBER, PRIMARY KEY (SHARD(id_cliente), id_carrito)) USING TTL 7 DAYS"

  table_limits {
    capacity_mode      = "ON_DEMAND"
    max_storage_in_gbs = 25
    max_read_units     = 0
    max_write_units    = 0
  }
}

resource "oci_nosql_index" "por_total" {
  table_name_or_id = oci_nosql_table.carritos.id
  compartment_id   = var.compartimento_id
  name             = "idx_total"

  keys {
    column_name = "total"
  }
}
