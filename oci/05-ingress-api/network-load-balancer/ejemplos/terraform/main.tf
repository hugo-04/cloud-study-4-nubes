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

variable "brokers" {
  type        = map(string)
  description = "Nombre => IP privada del broker"
  default     = { b1 = "10.0.3.11", b2 = "10.0.3.12", b3 = "10.0.3.13" }
}

# NLB privado para un clúster TCP interno (por ejemplo, brokers o una base)
resource "oci_network_load_balancer_network_load_balancer" "interno" {
  compartment_id                 = var.compartimento_id
  display_name                   = "nlb-brokers"
  subnet_id                      = var.subred_privada_id
  is_private                     = true
  is_preserve_source_destination = false
}

resource "oci_network_load_balancer_backend_set" "brokers" {
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.interno.id
  name                     = "brokers"
  policy                   = "FIVE_TUPLE"
  is_preserve_source       = true

  health_checker {
    protocol           = "HTTP"
    port               = 8081
    url_path           = "/salud"
    return_code        = 200
    interval_in_millis = 10000
    timeout_in_millis  = 3000
    retries            = 3
  }
}

resource "oci_network_load_balancer_backend" "brokers" {
  for_each                 = var.brokers
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.interno.id
  backend_set_name         = oci_network_load_balancer_backend_set.brokers.name
  name                     = each.key
  ip_address               = each.value
  port                     = 9093
}

resource "oci_network_load_balancer_listener" "tls" {
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.interno.id
  name                     = "tcp-9093"
  default_backend_set_name = oci_network_load_balancer_backend_set.brokers.name
  port                     = 9093
  protocol                 = "TCP"
}
