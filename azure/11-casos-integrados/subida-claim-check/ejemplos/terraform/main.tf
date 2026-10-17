terraform {
  required_version = ">= 1.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

variable "subscription_id" {
  type = string
}

variable "ubicacion" {
  type    = string
  default = "eastus2"
}

variable "entorno" {
  type = string
  validation {
    condition     = contains(["dev", "prod"], var.entorno)
    error_message = "entorno debe ser dev o prod."
  }
}

variable "origenes_web" {
  description = "Orígenes (https) desde los que el navegador sube directo a Blob."
  type        = list(string)
}

variable "identidad_api" {
  description = "Object ID de la identidad del servicio que emite las SAS."
  type        = string
}

variable "identidad_validador" {
  description = "Object ID de la identidad del servicio que valida y mueve los archivos."
  type        = string
}

locals {
  etiquetas = { app = "subidas", env = var.entorno, owner = "equipo-archivos" }
}

resource "azurerm_resource_group" "subidas" {
  name     = "rg-subidas-${var.entorno}"
  location = var.ubicacion
  tags     = local.etiquetas
}

resource "azurerm_storage_account" "subidas" {
  name                            = "stsubidas${var.entorno}001"
  resource_group_name             = azurerm_resource_group.subidas.name
  location                        = azurerm_resource_group.subidas.location
  account_tier                    = "Standard"
  account_replication_type        = "ZRS"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false # sin clave de cuenta: solo Entra ID y SAS de delegación de usuario
  tags                            = local.etiquetas

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 14
    }
    cors_rule {
      allowed_origins    = var.origenes_web
      allowed_methods    = ["PUT", "OPTIONS"]
      allowed_headers    = ["content-type", "x-ms-blob-type", "x-ms-version", "x-ms-date", "x-ms-client-request-id"]
      exposed_headers    = ["etag", "x-ms-request-id"]
      max_age_in_seconds = 600
    }
  }
}

# Zona de cuarentena: aquí aterriza TODO lo que sube un cliente. Nada de aquí se sirve ni se procesa.
resource "azurerm_storage_container" "cuarentena" {
  name                  = "cuarentena"
  storage_account_id    = azurerm_storage_account.subidas.id
  container_access_type = "private"
}

# Zona validada: solo el validador escribe; el resto del sistema lee de aquí.
resource "azurerm_storage_container" "validados" {
  name                  = "validados"
  storage_account_id    = azurerm_storage_account.subidas.id
  container_access_type = "private"
}

# Red de seguridad: lo que se quede en cuarentena más de un día se borra solo.
resource "azurerm_storage_management_policy" "limpieza" {
  storage_account_id = azurerm_storage_account.subidas.id

  rule {
    name    = "borrar-cuarentena-vieja"
    enabled = true
    filters {
      blob_types   = ["blockBlob"]
      prefix_match = ["cuarentena/"]
    }
    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = 1
      }
    }
  }

  rule {
    name    = "enfriar-validados"
    enabled = true
    filters {
      blob_types   = ["blockBlob"]
      prefix_match = ["validados/"]
    }
    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than = 30
      }
    }
  }
}

# Eventos de creación de blobs -> cola (la cola absorbe picos y permite reintentos).
resource "azurerm_storage_queue" "eventos" {
  name               = "eventos-cuarentena"
  storage_account_id = azurerm_storage_account.subidas.id
}

resource "azurerm_eventgrid_system_topic" "storage" {
  name                = "evgt-subidas-${var.entorno}"
  resource_group_name = azurerm_resource_group.subidas.name
  location            = azurerm_resource_group.subidas.location
  source_resource_id  = azurerm_storage_account.subidas.id
  topic_type          = "Microsoft.Storage.StorageAccounts"
  tags                = local.etiquetas

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_role_assignment" "topico_a_cola" {
  scope                = azurerm_storage_account.subidas.id
  role_definition_name = "Storage Queue Data Message Sender"
  principal_id         = azurerm_eventgrid_system_topic.storage.identity[0].principal_id
}

resource "azurerm_eventgrid_system_topic_event_subscription" "creados" {
  name                 = "blob-creado-en-cuarentena"
  system_topic         = azurerm_eventgrid_system_topic.storage.name
  resource_group_name  = azurerm_resource_group.subidas.name
  included_event_types = ["Microsoft.Storage.BlobCreated"]

  subject_filter {
    subject_begins_with = "/blobServices/default/containers/cuarentena/"
  }

  delivery_identity {
    type = "SystemAssigned"
  }

  storage_queue_endpoint {
    storage_account_id = azurerm_storage_account.subidas.id
    queue_name         = azurerm_storage_queue.eventos.name
  }

  retry_policy {
    max_delivery_attempts = 10
    event_time_to_live    = 1440
  }

  depends_on = [azurerm_role_assignment.topico_a_cola]
}

# Permisos mínimos por servicio (plano de datos)
resource "azurerm_role_assignment" "api_delegador" {
  scope                = azurerm_storage_account.subidas.id
  role_definition_name = "Storage Blob Delegator" # pedir la clave de delegación de usuario
  principal_id         = var.identidad_api
}

resource "azurerm_role_assignment" "api_cuarentena" {
  scope                = "${azurerm_storage_account.subidas.id}/blobServices/default/containers/${azurerm_storage_container.cuarentena.name}"
  role_definition_name = "Storage Blob Data Contributor" # una SAS de delegación hereda los permisos de quien la firma
  principal_id         = var.identidad_api
}

resource "azurerm_role_assignment" "validador_cuarentena" {
  scope                = "${azurerm_storage_account.subidas.id}/blobServices/default/containers/${azurerm_storage_container.cuarentena.name}"
  role_definition_name = "Storage Blob Data Contributor" # leer y borrar
  principal_id         = var.identidad_validador
}

resource "azurerm_role_assignment" "validador_validados" {
  scope                = "${azurerm_storage_account.subidas.id}/blobServices/default/containers/${azurerm_storage_container.validados.name}"
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.identidad_validador
}

resource "azurerm_role_assignment" "validador_cola" {
  scope                = azurerm_storage_queue.eventos.resource_manager_id
  role_definition_name = "Storage Queue Data Message Processor"
  principal_id         = var.identidad_validador
}

output "cuenta" {
  value = azurerm_storage_account.subidas.name
}
