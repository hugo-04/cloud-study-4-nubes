terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # terraform init -backend-config=backend.prod.hcl
  backend "s3" {}
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      entorno        = "prod"
      gestionado_por = "terraform"
    }
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "arn_limite_permisos" {
  description = "Límite de permisos de los roles de aplicación"
  type        = string
  default     = "arn:aws:iam::111122223333:policy/limite-permisos-aplicaciones"
}

# Mapa de servicios: la clave es el nombre y es estable. Lo puede generar un portal (ver uso en Java).
variable "servicios" {
  type = map(object({
    dueno                   = string
    equipo                  = string
    retencion_logs_dias     = optional(number, 30)
    max_receives            = optional(number, 5)
    retencion_mensajes_dias = optional(number, 4)
  }))
}

module "servicio" {
  source   = "../../modulos/servicio-base" # en producción real: git::https://github.com/modalima/modulos.git//servicio-base?ref=v1.3.0
  for_each = var.servicios

  nombre                  = each.key
  entorno                 = "prod"
  dueno                   = each.value.dueno
  equipo                  = each.value.equipo
  retencion_logs_dias     = each.value.retencion_logs_dias
  max_receives            = each.value.max_receives
  retencion_mensajes_dias = each.value.retencion_mensajes_dias
  arn_limite_permisos     = var.arn_limite_permisos
}

output "colas" {
  value = { for k, m in module.servicio : k => m.url_cola }
}
