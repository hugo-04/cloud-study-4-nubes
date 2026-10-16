# Azure RBAC con Terraform: rol de datos para un grupo y un rol personalizado.
# terraform init && terraform plan   (terraform destroy al terminar)

terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "grupo_object_id" {
  type        = string
  description = "Object ID del grupo de Entra ID que recibira el rol"
}

variable "ubicacion" {
  type    = string
  default = "eastus2"
}

data "azurerm_client_config" "actual" {}

resource "random_string" "sufijo" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-estudio-iam"
  location = var.ubicacion
}

resource "azurerm_storage_account" "st" {
  name                            = "strbac${random_string.sufijo.result}"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false # solo Entra ID (RBAC), sin claves de cuenta
}

resource "azurerm_storage_container" "fotos" {
  name                  = "fotos"
  storage_account_id    = azurerm_storage_account.st.id
  container_access_type = "private"
}

# Rol de DATOS al grupo, solo sobre el contenedor
resource "azurerm_role_assignment" "grupo_lee_fotos" {
  scope                = azurerm_storage_container.fotos.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = var.grupo_object_id
  principal_type       = "Group"
}

# Rol personalizado
resource "azurerm_role_definition" "soporte" {
  name        = "Soporte de Aplicaciones"
  scope       = "/subscriptions/${data.azurerm_client_config.actual.subscription_id}"
  description = "Reinicia sitios web y lee metricas. Nada mas."

  permissions {
    actions = [
      "Microsoft.Web/sites/read",
      "Microsoft.Web/sites/restart/action",
      "Microsoft.Insights/metrics/read",
    ]
    not_actions = []
  }

  assignable_scopes = [
    "/subscriptions/${data.azurerm_client_config.actual.subscription_id}",
  ]
}

resource "azurerm_role_assignment" "soporte_en_rg" {
  scope              = azurerm_resource_group.rg.id
  role_definition_id = azurerm_role_definition.soporte.role_definition_resource_id
  principal_id       = var.grupo_object_id
  principal_type     = "Group"
}
