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

variable "vcn_hub_id" {
  type = string
}

variable "vcn_spokes" {
  type        = map(string)
  description = "Mapa nombre -> OCID de cada VCN spoke (ej. prod, dev)"
}

locals {
  prefijo = "red-central"
}

resource "oci_core_drg" "central" {
  compartment_id = var.compartimento_red
  display_name   = "${local.prefijo}-drg"
}

# Tabla de la DRG para los SPOKES: todo lo que entre por un spoke va al hub (donde se inspecciona)
resource "oci_core_drg_route_table" "spokes" {
  drg_id       = oci_core_drg.central.id
  display_name = "${local.prefijo}-rt-spokes"
}

# Tabla de la DRG para el HUB: aprende las rutas de todos los spokes
resource "oci_core_drg_route_distribution" "hacia_hub" {
  drg_id            = oci_core_drg.central.id
  distribution_type = "IMPORT"
  display_name      = "${local.prefijo}-import-spokes"
}

resource "oci_core_drg_route_distribution_statement" "importar_vcn" {
  drg_route_distribution_id = oci_core_drg_route_distribution.hacia_hub.id
  action                    = "ACCEPT"
  priority                  = 1
  match_criteria {
    match_type      = "DRG_ATTACHMENT_TYPE"
    attachment_type = "VCN"
  }
}

resource "oci_core_drg_route_table" "hub" {
  drg_id                           = oci_core_drg.central.id
  display_name                     = "${local.prefijo}-rt-hub"
  import_drg_route_distribution_id = oci_core_drg_route_distribution.hacia_hub.id
}

resource "oci_core_drg_attachment" "hub" {
  drg_id       = oci_core_drg.central.id
  display_name = "${local.prefijo}-hub"
  network_details {
    id             = var.vcn_hub_id
    type           = "VCN"
    route_table_id = null
  }
  drg_route_table_id = oci_core_drg_route_table.hub.id
}

resource "oci_core_drg_attachment" "spoke" {
  for_each     = var.vcn_spokes
  drg_id       = oci_core_drg.central.id
  display_name = "${local.prefijo}-spoke-${each.key}"
  network_details {
    id   = each.value
    type = "VCN"
  }
  drg_route_table_id = oci_core_drg_route_table.spokes.id
}

# 0.0.0.0/0 en la tabla de spokes -> adjunto del hub
resource "oci_core_drg_route_table_route_rule" "spokes_al_hub" {
  drg_route_table_id         = oci_core_drg_route_table.spokes.id
  destination                = "0.0.0.0/0"
  destination_type           = "CIDR_BLOCK"
  next_hop_drg_attachment_id = oci_core_drg_attachment.hub.id
}

output "drg_id" {
  value = oci_core_drg.central.id
}
