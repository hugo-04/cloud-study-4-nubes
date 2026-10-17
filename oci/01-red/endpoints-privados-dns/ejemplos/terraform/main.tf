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

variable "compartimento_red" {
  type = string
}

variable "vcn_id" {
  type = string
}

variable "entorno" {
  type = string
}

variable "subred_endpoints_id" {
  type        = string
  description = "Subred donde viven los endpoints del resolutor"
}

variable "registros" {
  type        = map(string)
  description = "Nombre -> IP privada (ej. pedidos-db = 10.30.20.15)"
  default     = {}
}

locals {
  dominio = "${var.entorno}.tienda.interno"
}

data "oci_core_vcn_dns_resolver_association" "vcn" {
  vcn_id = var.vcn_id
}

resource "oci_dns_view" "privada" {
  compartment_id = var.compartimento_red
  scope          = "PRIVATE"
  display_name   = "${var.entorno}-tienda-vista"
}

resource "oci_dns_zone" "interna" {
  compartment_id = var.compartimento_red
  name           = local.dominio
  zone_type      = "PRIMARY"
  scope          = "PRIVATE"
  view_id        = oci_dns_view.privada.id
}

resource "oci_dns_rrset" "a" {
  for_each        = var.registros
  zone_name_or_id = oci_dns_zone.interna.id
  domain          = "${each.key}.${local.dominio}"
  rtype           = "A"
  scope           = "PRIVATE"
  view_id         = oci_dns_view.privada.id
  compartment_id  = var.compartimento_red
  items {
    domain = "${each.key}.${local.dominio}"
    rtype  = "A"
    rdata  = each.value
    ttl    = 300
  }
}

# La vista privada se asocia al resolutor de la VCN
resource "oci_dns_resolver" "vcn" {
  resolver_id = data.oci_core_vcn_dns_resolver_association.vcn.dns_resolver_id
  scope       = "PRIVATE"
  attached_views {
    view_id = oci_dns_view.privada.id
  }
}

output "dominio" {
  value = local.dominio
}
