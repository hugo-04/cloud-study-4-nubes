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
  type = string
}

variable "region" {
  type    = string
  default = "southamerica-west1"
}

variable "red_tienda" {
  type = string
}

variable "red_analitica" {
  type = string
}

variable "ip_oficina" {
  type        = string
  description = "IP pública del equipo VPN de la oficina"
}

variable "secreto_vpn" {
  type      = string
  sensitive = true
}

# Peering en ambos sentidos; tienda exporta sus rutas personalizadas (las de la VPN)
resource "google_compute_network_peering" "tienda_a_analitica" {
  name                 = "tienda-a-analitica"
  network              = var.red_tienda
  peer_network         = var.red_analitica
  export_custom_routes = true
}

resource "google_compute_network_peering" "analitica_a_tienda" {
  name                 = "analitica-a-tienda"
  network              = var.red_analitica
  peer_network         = var.red_tienda
  import_custom_routes = true
}

resource "google_compute_ha_vpn_gateway" "oficina" {
  name    = "vpn-oficina"
  region  = var.region
  network = var.red_tienda
}

resource "google_compute_external_vpn_gateway" "oficina" {
  name            = "equipo-oficina"
  redundancy_type = "SINGLE_IP_INTERNALLY_REDUNDANT"
  interface {
    id         = 0
    ip_address = var.ip_oficina
  }
}

resource "google_compute_router" "vpn" {
  name    = "router-vpn"
  region  = var.region
  network = var.red_tienda
  bgp {
    asn = 64514
  }
}

resource "google_compute_vpn_tunnel" "tunel" {
  count                           = 2
  name                            = "tunel-oficina-${count.index}"
  region                          = var.region
  vpn_gateway                     = google_compute_ha_vpn_gateway.oficina.id
  vpn_gateway_interface           = count.index
  peer_external_gateway           = google_compute_external_vpn_gateway.oficina.id
  peer_external_gateway_interface = 0
  shared_secret                   = var.secreto_vpn
  router                          = google_compute_router.vpn.id
  ike_version                     = 2
}

resource "google_compute_router_interface" "tunel" {
  count      = 2
  name       = "if-tunel-${count.index}"
  router     = google_compute_router.vpn.name
  region     = var.region
  ip_range   = "169.254.${count.index}.1/30"
  vpn_tunnel = google_compute_vpn_tunnel.tunel[count.index].name
}

resource "google_compute_router_peer" "oficina" {
  count                     = 2
  name                      = "bgp-oficina-${count.index}"
  router                    = google_compute_router.vpn.name
  region                    = var.region
  peer_ip_address           = "169.254.${count.index}.2"
  peer_asn                  = 65010
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.tunel[count.index].name
}
