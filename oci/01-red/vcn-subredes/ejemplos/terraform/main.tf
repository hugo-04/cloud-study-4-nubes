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
  # Local: usa ~/.oci/config. En pipelines: auth = "InstancePrincipal" o "ResourcePrincipal".
}

variable "region" {
  type    = string
  default = "sa-saopaulo-1"
}

variable "compartimento_red" {
  type        = string
  description = "OCID del compartimento donde vive la red"
}

variable "entorno" {
  type = string
}

variable "cidr_vcn" {
  type    = string
  default = "10.30.0.0/16"
  validation {
    condition     = can(cidrhost(var.cidr_vcn, 0))
    error_message = "cidr_vcn debe ser un CIDR válido."
  }
}

locals {
  prefijo = "${var.entorno}-tienda"
  etiquetas = {
    entorno = var.entorno
    sistema = "tienda"
  }
  # Planes de subred: /24 para balanceador, app y datos (253 IP utilizables cada una)
  subredes = {
    lb    = { cidr = cidrsubnet(var.cidr_vcn, 8, 0), publica = true }
    app   = { cidr = cidrsubnet(var.cidr_vcn, 8, 10), publica = false }
    datos = { cidr = cidrsubnet(var.cidr_vcn, 8, 20), publica = false }
  }
}

data "oci_core_services" "todos" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

resource "oci_core_vcn" "principal" {
  compartment_id = var.compartimento_red
  display_name   = "${local.prefijo}-vcn"
  cidr_blocks    = [var.cidr_vcn]
  dns_label      = replace("${var.entorno}tienda", "-", "")
  freeform_tags  = local.etiquetas
}

resource "oci_core_internet_gateway" "igw" {
  compartment_id = var.compartimento_red
  vcn_id         = oci_core_vcn.principal.id
  display_name   = "${local.prefijo}-igw"
  freeform_tags  = local.etiquetas
}

resource "oci_core_nat_gateway" "nat" {
  compartment_id = var.compartimento_red
  vcn_id         = oci_core_vcn.principal.id
  display_name   = "${local.prefijo}-nat"
  block_traffic  = false
  freeform_tags  = local.etiquetas
}

resource "oci_core_service_gateway" "sgw" {
  compartment_id = var.compartimento_red
  vcn_id         = oci_core_vcn.principal.id
  display_name   = "${local.prefijo}-sgw"
  services {
    service_id = data.oci_core_services.todos.services[0].id
  }
  freeform_tags = local.etiquetas
}

resource "oci_core_route_table" "publica" {
  compartment_id = var.compartimento_red
  vcn_id         = oci_core_vcn.principal.id
  display_name   = "${local.prefijo}-rt-publica"
  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.igw.id
  }
  freeform_tags = local.etiquetas
}

resource "oci_core_route_table" "privada" {
  compartment_id = var.compartimento_red
  vcn_id         = oci_core_vcn.principal.id
  display_name   = "${local.prefijo}-rt-privada"
  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.nat.id
  }
  route_rules {
    destination       = data.oci_core_services.todos.services[0].cidr_block
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.sgw.id
  }
  freeform_tags = local.etiquetas
}

resource "oci_core_route_table" "datos" {
  compartment_id = var.compartimento_red
  vcn_id         = oci_core_vcn.principal.id
  display_name   = "${local.prefijo}-rt-datos"
  # La base de datos solo habla con servicios de Oracle: sin salida a Internet
  route_rules {
    destination       = data.oci_core_services.todos.services[0].cidr_block
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.sgw.id
  }
  freeform_tags = local.etiquetas
}

resource "oci_core_subnet" "subred" {
  for_each                   = local.subredes
  compartment_id             = var.compartimento_red
  vcn_id                     = oci_core_vcn.principal.id
  display_name               = "${local.prefijo}-${each.key}"
  cidr_block                 = each.value.cidr
  dns_label                  = each.key
  prohibit_public_ip_on_vnic = !each.value.publica
  route_table_id             = each.key == "lb" ? oci_core_route_table.publica.id : each.key == "app" ? oci_core_route_table.privada.id : oci_core_route_table.datos.id
  freeform_tags              = local.etiquetas
}

output "subredes" {
  value = { for k, s in oci_core_subnet.subred : k => s.id }
}

output "vcn_id" {
  value = oci_core_vcn.principal.id
}
