# API Management con Terraform: servicio, identidad, named value desde Key Vault, backend, API importada de OpenAPI,
# política, producto + suscripción, version set y logger de Application Insights.
# terraform init && terraform plan
#
# AVISO: un APIM clásico (Developer/Premium) tarda 30-60 min en crearse/borrarse y Developer NO tiene SLA.
# "Consumption_0" se crea en minutos (menos funciones). Verifica los SKUs y límites vigentes (incluida la oferta v2).
# Soft-delete: tras borrar, el nombre queda reservado; azurerm puede purgarlo con features { api_management { purge_soft_delete_on_destroy = true } }.

terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {
    api_management {
      purge_soft_delete_on_destroy = true
      recover_soft_deleted         = false
    }
  }
}

variable "ubicacion" {
  type    = string
  default = "eastus2"
}

variable "sku" {
  description = "Developer_1 para estudiar; Premium_1 / Standard v2 para producción (verifica disponibilidad)"
  type        = string
  default     = "Developer_1"
}

variable "key_vault_secret_id" {
  description = "Secreto sin versión (se refresca solo)"
  type        = string
  default     = "https://kv-modalima-estudio01.vault.azure.net/secrets/clave-proveedor"
}

variable "key_vault_id" {
  type    = string
  default = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-estudio-kv/providers/Microsoft.KeyVault/vaults/kv-modalima-estudio01"
}

variable "backend_url" {
  type    = string
  default = "https://api-interna.modalima.example/pedidos"
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-estudio-apim"
  location = var.ubicacion
}

# ---------- Application Insights ----------
resource "azurerm_log_analytics_workspace" "law" {
  name                = "law-apim"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_application_insights" "ai" {
  name                = "appi-apim"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  workspace_id        = azurerm_log_analytics_workspace.law.id
  application_type    = "web"
}

# ---------- Servicio ----------
resource "azurerm_api_management" "apim" {
  name                = "apim-modalima-estudio"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  publisher_name      = "ModaLima"
  publisher_email     = "plataforma@modalima.example"
  sku_name            = var.sku

  identity {
    type = "SystemAssigned"
  }

  # Para el patrón empresarial (modo interno) añade:
  #   virtual_network_type = "Internal"
  #   virtual_network_configuration { subnet_id = azurerm_subnet.apim.id }
  # con subred dedicada y NSG (3443 desde ApiManagement, 6390 desde AzureLoadBalancer, 443).
}

# APIM lee el secreto del vault con su identidad administrada
resource "azurerm_role_assignment" "apim_kv" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_api_management.apim.identity[0].principal_id
}

resource "azurerm_api_management_logger" "ai" {
  name                = "appinsights"
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name

  application_insights {
    instrumentation_key = azurerm_application_insights.ai.instrumentation_key
  }
}

# ---------- Named values y backend ----------
resource "azurerm_api_management_named_value" "tenant" {
  name                = "tenant-id"
  resource_group_name = azurerm_resource_group.rg.name
  api_management_name = azurerm_api_management.apim.name
  display_name        = "tenant-id"
  value               = "00000000-0000-0000-0000-000000000000"
}

resource "azurerm_api_management_named_value" "clave_proveedor" {
  name                = "clave-proveedor"
  resource_group_name = azurerm_resource_group.rg.name
  api_management_name = azurerm_api_management.apim.name
  display_name        = "clave-proveedor"
  secret              = true

  value_from_key_vault {
    secret_id = var.key_vault_secret_id # sin versión: APIM la refresca
  }

  depends_on = [azurerm_role_assignment.apim_kv]
}

resource "azurerm_api_management_backend" "pedidos" {
  name                = "backend-pedidos"
  resource_group_name = azurerm_resource_group.rg.name
  api_management_name = azurerm_api_management.apim.name
  protocol            = "http"
  url                 = var.backend_url
}

# ---------- API versionada, importada de OpenAPI ----------
resource "azurerm_api_management_api_version_set" "pedidos" {
  name                = "pedidos"
  resource_group_name = azurerm_resource_group.rg.name
  api_management_name = azurerm_api_management.apim.name
  display_name        = "API de Pedidos"
  versioning_scheme   = "Segment" # /v1/pedidos, /v2/pedidos
}

resource "azurerm_api_management_api" "pedidos_v1" {
  name                  = "pedidos-v1"
  resource_group_name   = azurerm_resource_group.rg.name
  api_management_name   = azurerm_api_management.apim.name
  revision              = "1"
  display_name          = "Pedidos"
  path                  = "pedidos"
  protocols             = ["https"]
  version               = "v1"
  version_set_id        = azurerm_api_management_api_version_set.pedidos.id
  subscription_required = true

  import {
    content_format = "openapi+json"
    content_value  = file("${path.module}/../openapi/pedidos.json")
  }
}

resource "azurerm_api_management_api_policy" "pedidos_v1" {
  api_name            = azurerm_api_management_api.pedidos_v1.name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  xml_content         = file("${path.module}/../xml/10-api-policy.xml")

  depends_on = [azurerm_api_management_backend.pedidos, azurerm_api_management_named_value.tenant]
}

resource "azurerm_api_management_api_diagnostic" "pedidos_v1" {
  identifier               = "applicationinsights"
  resource_group_name      = azurerm_resource_group.rg.name
  api_management_name      = azurerm_api_management.apim.name
  api_name                 = azurerm_api_management_api.pedidos_v1.name
  api_management_logger_id = azurerm_api_management_logger.ai.id

  sampling_percentage       = 100
  always_log_errors         = true
  log_client_ip             = true
  verbosity                 = "error"
  http_correlation_protocol = "W3C"
}

# ---------- Producto y suscripción ----------
resource "azurerm_api_management_product" "socios" {
  product_id            = "socios-retail"
  api_management_name   = azurerm_api_management.apim.name
  resource_group_name   = azurerm_resource_group.rg.name
  display_name          = "Socios Retail"
  description           = "Solo lectura, 100 llamadas/min, 50 000/mes"
  subscription_required = true
  approval_required     = true
  published             = true
}

resource "azurerm_api_management_product_api" "socios_pedidos" {
  api_name            = azurerm_api_management_api.pedidos_v1.name
  product_id          = azurerm_api_management_product.socios.product_id
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_api_management_product_policy" "socios" {
  product_id          = azurerm_api_management_product.socios.product_id
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  xml_content         = file("${path.module}/../xml/20-producto-socio.xml")
}

resource "azurerm_api_management_subscription" "distribuidor" {
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  product_id          = azurerm_api_management_product.socios.id
  display_name        = "Distribuidor X"
  state               = "active"
}

output "gateway_url" {
  value = azurerm_api_management.apim.gateway_url
}

output "portal_url" {
  value = azurerm_api_management.apim.developer_portal_url
}
