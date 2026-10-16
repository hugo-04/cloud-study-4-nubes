# Function App Flex Consumption (Java 21) con Terraform: storage sin claves, identidad, Service Bus,
# conexiones por identidad y roles de datos.
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
  name     = "rg-estudio-func"
  location = var.ubicacion
}

# ---------- Storage del host y del paquete de despliegue ----------
resource "azurerm_storage_account" "st" {
  name                            = "stfunc${random_string.sufijo.result}"
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
}

resource "azurerm_storage_container" "paquete" {
  name                  = "app-package"
  storage_account_id    = azurerm_storage_account.st.id
  container_access_type = "private"
}

# ---------- Identidad ----------
resource "azurerm_user_assigned_identity" "func" {
  name                = "id-func-pedidos"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

locals {
  roles_storage = [
    "Storage Blob Data Owner",
    "Storage Queue Data Contributor",
    "Storage Table Data Contributor",
  ]
}

resource "azurerm_role_assignment" "storage" {
  for_each             = toset(local.roles_storage)
  scope                = azurerm_storage_account.st.id
  role_definition_name = each.value
  principal_id         = azurerm_user_assigned_identity.func.principal_id
  principal_type       = "ServicePrincipal"
}

# ---------- Service Bus ----------
resource "azurerm_servicebus_namespace" "sb" {
  name                = "sb-func-${random_string.sufijo.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"
  local_auth_enabled  = false # solo Entra ID
}

resource "azurerm_servicebus_queue" "pedidos" {
  name                                 = "pedidos"
  namespace_id                         = azurerm_servicebus_namespace.sb.id
  max_delivery_count                   = 5
  lock_duration                        = "PT1M"
  dead_lettering_on_message_expiration = true
}

resource "azurerm_servicebus_queue" "facturas" {
  name         = "facturas"
  namespace_id = azurerm_servicebus_namespace.sb.id
}

resource "azurerm_role_assignment" "sb_recibe" {
  scope                = azurerm_servicebus_namespace.sb.id
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = azurerm_user_assigned_identity.func.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "sb_envia" {
  scope                = azurerm_servicebus_namespace.sb.id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = azurerm_user_assigned_identity.func.principal_id
  principal_type       = "ServicePrincipal"
}

# ---------- Function App (Flex Consumption) ----------
resource "azurerm_service_plan" "flex" {
  name                = "plan-func-flex"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  os_type             = "Linux"
  sku_name            = "FC1"
}

resource "azurerm_function_app_flex_consumption" "func" {
  name                = "func-modalima-${random_string.sufijo.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  service_plan_id     = azurerm_service_plan.flex.id

  storage_container_type            = "blobContainer"
  storage_container_endpoint        = "${azurerm_storage_account.st.primary_blob_endpoint}${azurerm_storage_container.paquete.name}"
  storage_authentication_type       = "UserAssignedIdentity"
  storage_user_assigned_identity_id = azurerm_user_assigned_identity.func.id

  runtime_name           = "java"
  runtime_version        = "21"
  maximum_instance_count = 40
  instance_memory_in_mb  = 2048

  always_ready {
    name           = "http"
    instance_count = 2
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.func.id]
  }

  site_config {}

  app_settings = {
    AzureWebJobsStorage__accountName = azurerm_storage_account.st.name
    AzureWebJobsStorage__credential  = "managedidentity"
    AzureWebJobsStorage__clientId    = azurerm_user_assigned_identity.func.client_id

    SBCONN__fullyQualifiedNamespace = "${azurerm_servicebus_namespace.sb.name}.servicebus.windows.net"
    SBCONN__credential              = "managedidentity"
    SBCONN__clientId                = azurerm_user_assigned_identity.func.client_id

    AZURE_CLIENT_ID = azurerm_user_assigned_identity.func.client_id
  }

  depends_on = [azurerm_role_assignment.storage]
}

output "func_host" {
  value = azurerm_function_app_flex_consumption.func.default_hostname
}
