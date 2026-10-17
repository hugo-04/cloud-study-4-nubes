# Composición de ejemplo: varias aplicaciones con el mismo módulo, dos suscripciones y cirugía del estado.
# El módulo vive en ../modulos/app-base (en la vida real: un repositorio propio con etiquetas de versión).

terraform {
  required_version = ">= 1.7"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.0"
    }
  }
}

provider "azurerm" {
  features {}

  subscription_id     = var.subscription_id
  storage_use_azuread = true
}

# Segunda suscripción (por ejemplo, la de plataforma con DNS privado compartido)
provider "azurerm" {
  alias = "plataforma"

  features {}

  subscription_id = var.subscription_plataforma
}

provider "azapi" {
  subscription_id = var.subscription_id
}

variable "subscription_id" {
  type        = string
  description = "Suscripción del entorno."
}

variable "subscription_plataforma" {
  type        = string
  description = "Suscripción de plataforma."
}

variable "ubicacion" {
  type    = string
  default = "eastus2"
}

variable "entorno" {
  type        = string
  description = "dev, qa o prod."
}

variable "aplicaciones" {
  description = "Una entrada por aplicación. La clave es el nombre corto (estable: es parte de la dirección en el estado)."
  type = map(object({
    dueno        = string
    contenedores = optional(set(string), [])
    ips          = optional(list(string), [])
    replicacion  = optional(string, "ZRS")
  }))
}

# ---- Un módulo, muchas instancias (for_each con clave estable) -------------------------
module "app" {
  source   = "../modulos/app-base"
  for_each = var.aplicaciones

  nombre_aplicacion = each.key
  entorno           = var.entorno
  ubicacion         = var.ubicacion
  dueno             = each.value.dueno
  contenedores      = each.value.contenedores
  ips_permitidas    = each.value.ips
  replicacion       = each.value.replicacion
}

# ---- Cirugía del estado, en el código y bajo revisión ------------------------------
# 1) Antes había un único "module.pedidos"; ahora es una instancia de for_each. Sin esto, Terraform destruiría y recrearía.
moved {
  from = module.pedidos
  to   = module.app["pedidos"]
}

# 2) Traer a Terraform un grupo de recursos que ya existe en Azure (sin recrearlo).
import {
  to = azurerm_resource_group.heredado
  id = "/subscriptions/${var.subscription_id}/resourceGroups/rg-heredado-${var.entorno}"
}

resource "azurerm_resource_group" "heredado" {
  name     = "rg-heredado-${var.entorno}"
  location = var.ubicacion
}

# 3) Dejar de administrar un recurso SIN borrarlo en Azure.
removed {
  from = azurerm_resource_group.antiguo

  lifecycle {
    destroy = false
  }
}

# ---- Un recurso que azurerm todavía no cubre: azapi (API de ARM directa) -------------
resource "azapi_resource" "grupo_via_arm" {
  type      = "Microsoft.Resources/resourceGroups@2024-03-01"
  name      = "rg-via-azapi-${var.entorno}"
  parent_id = "/subscriptions/${var.subscription_id}"
  location  = var.ubicacion

  body = {
    properties = {}
    tags = {
      gestionado = "terraform"
    }
  }
}

# ---- Zona DNS privada en la OTRA suscripción (proveedor con alias) ---------------------
resource "azurerm_resource_group" "dns_compartido" {
  provider = azurerm.plataforma

  name     = "rg-dns-compartido"
  location = var.ubicacion
}

# ---- Comprobaciones que avisan sin detener ------------------------------------------------
check "aplicaciones_tienen_dueno" {
  assert {
    condition     = alltrue([for k, a in var.aplicaciones : length(trimspace(a.dueno)) > 0])
    error_message = "Toda aplicación debe tener un dueño."
  }
}

output "cuentas" {
  description = "Cuenta de almacenamiento de cada aplicación."
  value       = { for k, m in module.app : k => m.cuenta_nombre }
}
