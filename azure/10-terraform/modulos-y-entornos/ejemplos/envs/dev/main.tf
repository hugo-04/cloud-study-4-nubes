# Raíz del entorno DEV: una carpeta por entorno, con su estado, sus variables y sus permisos.
terraform {
  required_version = ">= 1.7, < 2.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  backend "azurerm" {
    key = "dev/aplicaciones.tfstate" # cuenta y contenedor: -backend-config=backend.dev.hcl
  }
}

provider "azurerm" {
  features {}

  use_oidc            = true
  storage_use_azuread = true
}

variable "aplicaciones" {
  type = map(object({
    dueno        = string
    contenedores = optional(set(string), [])
    ips          = optional(list(string), [])
    replicacion  = optional(string, "LRS")
  }))
}

module "app" {
  # En producción: "git::https://github.com/modalima/tf-modulos.git//app-base?ref=v1.3.0" (versión fija)
  source   = "../../modulos/app-base"
  for_each = var.aplicaciones

  nombre_aplicacion = each.key
  entorno           = "dev"
  dueno             = each.value.dueno
  contenedores      = each.value.contenedores
  ips_permitidas    = each.value.ips
  replicacion       = each.value.replicacion
  restringir_red    = false # dev: más libre
}

output "cuentas" {
  value = { for k, m in module.app : k => m.cuenta_nombre }
}
