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
  type        = string
  description = "NSG: 6379/TCP solo desde las apps"
}

resource "oci_redis_redis_cluster" "catalogo" {
  compartment_id     = var.compartimento_id
  display_name       = "cache-catalogo"
  node_count         = 3
  node_memory_in_gbs = 8
  software_version   = "VALKEY_7_2"
  subnet_id          = var.subred_privada_id
  nsg_ids            = [var.nsg_id]

  freeform_tags = {
    proyecto = "modalima"
  }
}

output "primario" {
  value = oci_redis_redis_cluster.catalogo.primary_fqdn
}

output "replicas" {
  value = oci_redis_redis_cluster.catalogo.replicas_fqdn
}
