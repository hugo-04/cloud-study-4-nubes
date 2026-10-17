# Fragmentos para consultar: convenciones de nombres, etiquetas, lifecycle y validaciones.
# (Es una raíz válida por sí sola; cópiala a un directorio y ejecuta terraform validate.)

terraform {
  required_version = ">= 1.7"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}

  subscription_id = "00000000-0000-0000-0000-000000000000"
}

locals {
  organizacion = "modalima"
  entorno      = "prod"
  region_corta = { eastus2 = "eus2", westus3 = "wus3" }["eastus2"]

  # Convención: <tipo>-<aplicación>-<entorno>-<región>  (los límites de cada tipo están en la documentación de nombres)
  nombre = {
    grupo  = "rg-pedidos-${local.entorno}-${local.region_corta}"
    cuenta = "stpedidos${local.entorno}001"
    boveda = "kv-pedidos-${local.entorno}"
  }

  etiquetas_base = {
    organizacion = local.organizacion
    entorno      = local.entorno
    gestionado   = "terraform"
  }
}

resource "azurerm_resource_group" "ejemplo" {
  name     = local.nombre.grupo
  location = "eastus2"
  tags     = merge(local.etiquetas_base, { dueno = "equipo-pedidos" })

  lifecycle {
    # Nunca destruir sin un cambio explícito de código (protege contra un plan accidental)
    prevent_destroy = false # pon true en producción

    # Etiquetas que pone una política de Azure: Terraform no debe pelearse con ellas
    ignore_changes = [tags["costcenter"]]
  }
}

resource "azurerm_storage_account" "ejemplo" {
  name                     = local.nombre.cuenta
  resource_group_name      = azurerm_resource_group.ejemplo.name
  location                 = azurerm_resource_group.ejemplo.location
  account_tier             = "Standard"
  account_replication_type = "ZRS"

  shared_access_key_enabled = false

  lifecycle {
    # Antes de planificar: el nombre debe cumplir el límite de Azure
    precondition {
      condition     = length(local.nombre.cuenta) >= 3 && length(local.nombre.cuenta) <= 24
      error_message = "El nombre de la cuenta debe tener entre 3 y 24 caracteres."
    }

    # Después de aplicar: el resultado debe cumplir lo que prometimos
    postcondition {
      condition     = self.min_tls_version == "TLS1_2"
      error_message = "La cuenta quedó con un TLS mínimo inferior a 1.2."
    }

  }
}
