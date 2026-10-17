# Composición de la landing zone de ModaLima: una llamada al módulo por equipo y entorno.
# Los proveedores no pueden ser dinámicos: hay un bloque `provider` por suscripción (el costo de la claridad).

terraform {
  required_version = ">= 1.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

variable "suscripcion_plataforma" {
  type = string
}

variable "suscripcion_pedidos_prod" {
  type = string
}

variable "suscripcion_catalogo_dev" {
  type = string
}

variable "grupo_corp_id" {
  type = string
}

variable "grupo_online_id" {
  type = string
}

variable "grupo_sandbox_id" {
  type = string
}

variable "grupo_pedidos" {
  type = string
}

variable "grupo_catalogo" {
  type = string
}

variable "red_hub_id" {
  type = string
}

variable "workspace_central_id" {
  type = string
}

provider "azurerm" {
  alias = "plataforma"
  features {}
  subscription_id = var.suscripcion_plataforma
}

provider "azurerm" {
  alias = "pedidos_prod"
  features {}
  subscription_id = var.suscripcion_pedidos_prod
}

provider "azurerm" {
  alias = "catalogo_dev"
  features {}
  subscription_id = var.suscripcion_catalogo_dev
}

module "pedidos_prod" {
  source = "./modulos/suscripcion-de-carga"
  providers = {
    azurerm.destino    = azurerm.pedidos_prod
    azurerm.plataforma = azurerm.plataforma
  }

  equipo                     = "pedidos"
  entorno                    = "prod"
  subscription_id            = var.suscripcion_pedidos_prod
  grupo_de_administracion_id = var.grupo_online_id
  grupo_del_equipo           = var.grupo_pedidos
  propietario                = "pedidos@modalima.example"
  centro_de_costo            = "CC-1001"
  presupuesto_mensual        = 8000
  correos_de_alerta          = ["pedidos@modalima.example", "finops@modalima.example"]
  cidr_red                   = "10.40.0.0/22" # asignado por el servicio de direcciones
  red_hub_id                 = var.red_hub_id
  red_hub_nombre             = "vnet-hub"
  red_hub_grupo_de_recursos  = "rg-conectividad"
  workspace_central_id       = var.workspace_central_id
}

module "catalogo_dev" {
  source = "./modulos/suscripcion-de-carga"
  providers = {
    azurerm.destino    = azurerm.catalogo_dev
    azurerm.plataforma = azurerm.plataforma
  }

  equipo                     = "catalogo"
  entorno                    = "dev"
  subscription_id            = var.suscripcion_catalogo_dev
  grupo_de_administracion_id = var.grupo_sandbox_id
  grupo_del_equipo           = var.grupo_catalogo
  propietario                = "catalogo@modalima.example"
  centro_de_costo            = "CC-2002"
  presupuesto_mensual        = 600
  correos_de_alerta          = ["catalogo@modalima.example"]
  cidr_red                   = "10.40.8.0/24"
  red_hub_id                 = var.red_hub_id
  red_hub_nombre             = "vnet-hub"
  red_hub_grupo_de_recursos  = "rg-conectividad"
  workspace_central_id       = var.workspace_central_id
}

output "redes" {
  value = {
    pedidos_prod = module.pedidos_prod.red_id
    catalogo_dev = module.catalogo_dev.red_id
  }
}
