# Composición raíz de prod/tienda: usa el módulo con variables de prod.
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

variable "nsg_lb_id" {
  type = string
}

locals {
  # En producción: source = "git::https://git.example/infra/modulos.git//microservicio?ref=v2.1.0"
  servicios = {
    catalogo = 8080
    pedidos  = 8080
    pagos    = 8443
  }
}

module "servicio" {
  source           = "../modulos/microservicio"
  for_each         = local.servicios
  nombre           = each.key
  entorno          = "prod"
  compartimento_id = var.compartimento_id
  vcn_id           = var.vcn_id
  puerto           = each.value
  nsg_origen_id    = var.nsg_lb_id
}

# Si renombras el módulo, declara el movimiento para no destruir nada:
# moved {
#   from = module.app
#   to   = module.servicio
# }

output "nsg_por_servicio" {
  value = { for k, m in module.servicio : k => m.nsg_id }
}
