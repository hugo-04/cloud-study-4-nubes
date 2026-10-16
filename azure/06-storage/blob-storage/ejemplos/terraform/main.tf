# Blob Storage de producción (referencia):
#  cuenta ZRS sin claves ni acceso público, TLS 1.2, red cerrada + Private Endpoint con zona DNS privada,
#  soft delete, versionado, change feed, CORS para subidas desde el navegador, ciclo de vida, contenedores,
#  RBAC para la aplicación y diagnósticos hacia Log Analytics.
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
  storage_use_azuread = true # operaciones de datos con Entra ID (la cuenta no tiene claves)
}

variable "ubicacion" {
  type    = string
  default = "eastus2"
}

variable "origenes_cors" {
  description = "Sitios web que subirán directo con SAS"
  type        = list(string)
  default     = ["https://tienda.modalima.example"]
}

variable "principal_app_id" {
  description = "Object id de la identidad de la aplicación (identidad administrada)"
  type        = string
  default     = "00000000-0000-0000-0000-000000000001"
}

resource "random_string" "sufijo" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-estudio-storage"
  location = var.ubicacion
}

# ---------- Red para el Private Endpoint ----------
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-storage"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.97.0.0/16"]
}

resource "azurerm_subnet" "pe" {
  name                 = "snet-private-endpoints"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.97.1.0/24"]
}

# ---------- Cuenta ----------
resource "azurerm_storage_account" "st" {
  name                     = "stmodalima${random_string.sufijo.result}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "ZRS"
  access_tier              = "Hot"

  # Seguridad
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  allow_nested_items_to_be_public   = false
  shared_access_key_enabled         = false # solo Entra ID o SAS de delegación de usuario
  default_to_oauth_authentication   = true
  public_network_access_enabled     = false # solo privado
  infrastructure_encryption_enabled = true

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }

  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true

    delete_retention_policy {
      days = 14
    }

    container_delete_retention_policy {
      days = 14
    }

    restore_policy {
      days = 7
    }

    cors_rule {
      allowed_origins    = var.origenes_cors
      allowed_methods    = ["GET", "PUT", "HEAD", "OPTIONS"]
      allowed_headers    = ["*"]
      exposed_headers    = ["ETag", "x-ms-request-id"]
      max_age_in_seconds = 3600
    }
  }
}

resource "azurerm_storage_container" "fotos" {
  name                  = "fotos"
  storage_account_id    = azurerm_storage_account.st.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "subidas" {
  name                  = "subidas"
  storage_account_id    = azurerm_storage_account.st.id
  container_access_type = "private"
}

# ---------- Ciclo de vida ----------
resource "azurerm_storage_management_policy" "ciclo" {
  storage_account_id = azurerm_storage_account.st.id

  rule {
    name    = "enfriar-y-borrar-logs"
    enabled = true

    filters {
      prefix_match = ["logs/"]
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = 30
        tier_to_archive_after_days_since_modification_greater_than = 180
        delete_after_days_since_modification_greater_than          = 730
      }

      version {
        change_tier_to_cool_after_days_since_creation = 30
        delete_after_days_since_creation              = 90
      }

      snapshot {
        delete_after_days_since_creation_greater_than = 30
      }
    }
  }

  rule {
    name    = "procesados-a-frio"
    enabled = true

    filters {
      prefix_match = ["subidas/"]
      blob_types   = ["blockBlob"]

      match_blob_index_tag {
        name      = "estado"
        operation = "=="
        value     = "procesado"
      }
    }

    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than = 7
        delete_after_days_since_modification_greater_than       = 90
      }
    }
  }
}

# ---------- Private Endpoint + DNS privado ----------
resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                  = "enlace-vnet-storage"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

resource "azurerm_private_endpoint" "blob" {
  name                = "pe-st-blob"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.pe.id

  private_service_connection {
    name                           = "psc-blob"
    private_connection_resource_id = azurerm_storage_account.st.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-blob"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }
}

# ---------- RBAC para la aplicación ----------
resource "azurerm_role_assignment" "app_datos" {
  scope                = "${azurerm_storage_account.st.id}/blobServices/default/containers/${azurerm_storage_container.subidas.name}"
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.principal_app_id
}

resource "azurerm_role_assignment" "app_delegator" {
  scope                = azurerm_storage_account.st.id # Delegator solo se asigna a nivel de cuenta/RG/suscripción
  role_definition_name = "Storage Blob Delegator"
  principal_id         = var.principal_app_id
}

# ---------- Diagnósticos ----------
resource "azurerm_log_analytics_workspace" "law" {
  name                = "law-storage"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_monitor_diagnostic_setting" "blob" {
  name                       = "diag-blob"
  target_resource_id         = "${azurerm_storage_account.st.id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }

  enabled_metric {
    category = "Transaction"
  }
}

output "nombre_cuenta" {
  value = azurerm_storage_account.st.name
}

output "endpoint_blob" {
  value = azurerm_storage_account.st.primary_blob_endpoint
}
