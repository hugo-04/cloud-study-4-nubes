# Proveedor y backend para pipelines con OIDC (sin secretos).
# Las credenciales NO van en el código: llegan por variables de entorno del pipeline.
#   ARM_USE_OIDC=true   ARM_CLIENT_ID=...   ARM_TENANT_ID=...   ARM_SUBSCRIPTION_ID=...
# En GitHub Actions el proveedor obtiene el token solo (el trabajo necesita permissions: id-token: write).

terraform {
  required_version = ">= 1.6, < 2.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  backend "azurerm" {
    # Solo la clave va en el código; cuenta, contenedor y método de autenticación van en backend.<entorno>.hcl
    key = "prod/app-pedidos.tfstate"
  }
}

provider "azurerm" {
  features {}

  use_oidc = true
  # subscription_id, client_id y tenant_id: ARM_SUBSCRIPTION_ID, ARM_CLIENT_ID, ARM_TENANT_ID
  # Con claves de la cuenta desactivadas, el proveedor usa Entra ID también para operaciones de datos:
  storage_use_azuread = true
}
