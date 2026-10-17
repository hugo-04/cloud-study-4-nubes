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

variable "vcn_id" {
  type = string
}

variable "nsg_pods_id" {
  type        = string
  description = "NSG de los pods (o de los nodos si se usa NodePort)"
}

# IP pública reservada para el LB del Ingress (se referencia desde IngressClassParameters o la anotación)
resource "oci_core_public_ip" "ingress" {
  compartment_id = var.compartimento_id
  lifetime       = "RESERVED"
  display_name   = "ip-ingress-tienda"

  lifecycle {
    prevent_destroy = true
  }
}

# NSG del LB: HTTPS desde Internet
resource "oci_core_network_security_group" "lb" {
  compartment_id = var.compartimento_id
  vcn_id         = var.vcn_id
  display_name   = "nsg-lb-ingress"
}

resource "oci_core_network_security_group_security_rule" "https_entrada" {
  network_security_group_id = oci_core_network_security_group.lb.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source_type               = "CIDR_BLOCK"
  source                    = "0.0.0.0/0"
  tcp_options {
    destination_port_range {
      min = 443
      max = 443
    }
  }
}

# Los pods solo aceptan tráfico de aplicación desde el NSG del LB
resource "oci_core_network_security_group_security_rule" "pods_desde_lb" {
  network_security_group_id = var.nsg_pods_id
  direction                 = "INGRESS"
  protocol                  = "6"
  source_type               = "NETWORK_SECURITY_GROUP"
  source                    = oci_core_network_security_group.lb.id
  tcp_options {
    destination_port_range {
      min = 8080
      max = 8080
    }
  }
}

output "ip_reservada" {
  value = oci_core_public_ip.ingress.ip_address
}

output "nsg_lb" {
  value = oci_core_network_security_group.lb.id
}
