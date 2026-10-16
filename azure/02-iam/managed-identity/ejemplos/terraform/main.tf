# Managed Identity user-assigned: identidad, storage, rol de datos y Web App.
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

variable "ubicacion" {
  type    = string
  default = "eastus2"
}

resource "random_string" "sufijo" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-estudio-mi"
  location = var.ubicacion
}

# La identidad y sus roles existen ANTES que la aplicacion (evita carreras de despliegue)
resource "azurerm_user_assigned_identity" "api_pedidos" {
  name                = "id-api-pedidos"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_storage_account" "st" {
  name                            = "stmi${random_string.sufijo.result}"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
}

resource "azurerm_role_assignment" "lee_blobs" {
  scope                = azurerm_storage_account.st.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.api_pedidos.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_service_plan" "plan" {
  name                = "plan-estudio-mi"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  os_type             = "Linux"
  sku_name            = "B1"
}

resource "azurerm_linux_web_app" "app" {
  name                = "app-estudio-mi-${random_string.sufijo.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  service_plan_id     = azurerm_service_plan.plan.id

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.api_pedidos.id]
  }

  site_config {
    application_stack {
      java_server         = "JAVA"
      java_server_version = "21"
      java_version        = "21"
    }
  }

  app_settings = {
    AZURE_CLIENT_ID = azurerm_user_assigned_identity.api_pedidos.client_id
    STORAGE_ACCOUNT = azurerm_storage_account.st.name
  }

  depends_on = [azurerm_role_assignment.lee_blobs]
}

output "client_id_de_la_identidad" {
  value = azurerm_user_assigned_identity.api_pedidos.client_id
}
