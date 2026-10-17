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

variable "puerto_app" {
  type    = number
  default = 8080
}

variable "puerto_db" {
  type    = number
  default = 5432
}

locals {
  prefijo = "${var.entorno}-tienda"
}

# Un NSG por rol
resource "oci_core_network_security_group" "lb" {
  compartment_id = var.compartimento_red
  vcn_id         = var.vcn_id
  display_name   = "${local.prefijo}-nsg-lb"
}

resource "oci_core_network_security_group" "app" {
  compartment_id = var.compartimento_red
  vcn_id         = var.vcn_id
  display_name   = "${local.prefijo}-nsg-app"
}

resource "oci_core_network_security_group" "datos" {
  compartment_id = var.compartimento_red
  vcn_id         = var.vcn_id
  display_name   = "${local.prefijo}-nsg-datos"
}

# Internet -> balanceador (443)
resource "oci_core_network_security_group_security_rule" "lb_entrada" {
  network_security_group_id = oci_core_network_security_group.lb.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  description               = "HTTPS público hacia el balanceador"
  tcp_options {
    destination_port_range {
      min = 443
      max = 443
    }
  }
}

# Balanceador -> app (solo desde el NSG del balanceador)
resource "oci_core_network_security_group_security_rule" "app_entrada" {
  network_security_group_id = oci_core_network_security_group.app.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = oci_core_network_security_group.lb.id
  source_type               = "NETWORK_SECURITY_GROUP"
  description               = "Tráfico del balanceador hacia la aplicación"
  tcp_options {
    destination_port_range {
      min = var.puerto_app
      max = var.puerto_app
    }
  }
}

resource "oci_core_network_security_group_security_rule" "lb_salida_app" {
  network_security_group_id = oci_core_network_security_group.lb.id
  direction                 = "EGRESS"
  protocol                  = "6"
  destination               = oci_core_network_security_group.app.id
  destination_type          = "NETWORK_SECURITY_GROUP"
  description               = "El balanceador solo habla con la aplicación"
  tcp_options {
    destination_port_range {
      min = var.puerto_app
      max = var.puerto_app
    }
  }
}

# App -> datos
resource "oci_core_network_security_group_security_rule" "datos_entrada" {
  network_security_group_id = oci_core_network_security_group.datos.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = oci_core_network_security_group.app.id
  source_type               = "NETWORK_SECURITY_GROUP"
  description               = "La aplicación consulta la base de datos"
  tcp_options {
    destination_port_range {
      min = var.puerto_db
      max = var.puerto_db
    }
  }
}

# App -> salida (Internet por NAT y servicios por SGW; ajusta si necesitas más restricción)
resource "oci_core_network_security_group_security_rule" "app_salida" {
  network_security_group_id = oci_core_network_security_group.app.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
  description               = "Salida de la aplicación (a restringir por FQDN o firewall si se requiere)"
}

# Lista de seguridad mínima: solo ICMP de descubrimiento de MTU
resource "oci_core_security_list" "minima" {
  compartment_id = var.compartimento_red
  vcn_id         = var.vcn_id
  display_name   = "${local.prefijo}-sl-minima"
  ingress_security_rules {
    protocol    = "1"
    source      = "0.0.0.0/0"
    description = "ICMP tipo 3 código 4: descubrimiento de MTU"
    icmp_options {
      type = 3
      code = 4
    }
  }
}

output "nsg" {
  value = {
    lb    = oci_core_network_security_group.lb.id
    app   = oci_core_network_security_group.app.id
    datos = oci_core_network_security_group.datos.id
  }
}
