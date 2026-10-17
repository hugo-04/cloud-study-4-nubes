terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      gestionado_por = "terraform"
    }
  }
}

variable "servicios" {
  description = "Servicios a crear (mapa con clave estable)"
  type = map(object({
    dueno  = string
    equipo = string
  }))
  default = {
    catalogo = { dueno = "equipo-catalogo@modalima.example", equipo = "catalogo" }
    pedidos  = { dueno = "equipo-pedidos@modalima.example", equipo = "pedidos" }
  }
}

module "servicio" {
  source   = "../modulos/servicio-base"
  for_each = var.servicios

  nombre  = each.key
  entorno = "dev"
  dueno   = each.value.dueno
  equipo  = each.value.equipo
}

output "colas" {
  value = { for k, m in module.servicio : k => m.url_cola }
}
