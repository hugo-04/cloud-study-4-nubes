# Claim Check en Azure: Blob (almacén) + Service Bus (canal) + Event Grid (variante por eventos) + roles.
#   - Cuenta de storage SIN clave compartida, con versionado y soft delete (el ticket apunta a una versión)
#   - Service Bus SIN cadenas de conexión (local_auth_enabled = false)
#   - Cola "archivos": tickets publicados por el backend (variantes A y C), con detección de duplicados
#   - Cola "eventos-blob": BlobCreated entregado por Event Grid con su identidad (variante B)
#   - Roles mínimos para productor, consumidor y Event Grid
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
  storage_use_azuread = true
}

variable "ubicacion" {
  type    = string
  default = "eastus2"
}

variable "principal_productor" {
  description = "Object id de la identidad del backend que sube el blob y publica el ticket"
  type        = string
  default     = "00000000-0000-0000-0000-000000000001"
}

variable "principal_consumidor" {
  description = "Object id de la identidad del procesador"
  type        = string
  default     = "00000000-0000-0000-0000-000000000002"
}

resource "random_string" "sufijo" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-estudio-claimcheck"
  location = var.ubicacion
}

# ---------------------------------------------------------------- Almacén
resource "azurerm_storage_account" "st" {
  name                            = "stcc${random_string.sufijo.result}"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  account_tier                    = "Standard"
  account_replication_type        = "ZRS"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false

  blob_properties {
    versioning_enabled = true # el ticket lleva blobVersionId: lee EXACTAMENTE lo anunciado

    delete_retention_policy {
      days = 14 # >= vida del mensaje (TTL de la cola) para evitar BLOB_AUSENTE
    }

    container_delete_retention_policy {
      days = 14
    }
  }
}

resource "azurerm_storage_container" "subidas" {
  name                  = "subidas"
  storage_account_id    = azurerm_storage_account.st.id
  container_access_type = "private"
}

# Limpieza: huérfanos (sin confirmar) y ya procesados. Las versiones antiguas se borran aparte.
resource "azurerm_storage_management_policy" "limpieza" {
  storage_account_id = azurerm_storage_account.st.id

  rule {
    name    = "huerfanos-sin-confirmar"
    enabled = true

    filters {
      prefix_match = ["subidas/usuarios/"]
      blob_types   = ["blockBlob"]

      match_blob_index_tag {
        name      = "estado"
        operation = "=="
        value     = "sin-confirmar"
      }
    }

    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = 2
      }
    }
  }

  rule {
    name    = "procesados"
    enabled = true

    filters {
      prefix_match = ["subidas/usuarios/"]
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
      version {
        delete_after_days_since_creation = 30
      }
    }
  }
}

# ---------------------------------------------------------------- Canal
resource "azurerm_servicebus_namespace" "sb" {
  name                = "sb-cc-${random_string.sufijo.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Standard"
  local_auth_enabled  = false # solo Entra ID: sin SharedAccessKey
  minimum_tls_version = "1.2"
}

# Tickets del backend (variantes A y C)
resource "azurerm_servicebus_queue" "archivos" {
  name         = "archivos"
  namespace_id = azurerm_servicebus_namespace.sb.id

  lock_duration                           = "PT5M" # máximo del bloqueo: renueva en procesos largos
  max_delivery_count                      = 5      # después, a la DLQ
  default_message_ttl                     = "P7D"
  requires_duplicate_detection            = true # descarta el mismo MessageId dentro de la ventana
  duplicate_detection_history_time_window = "PT10M"
  dead_lettering_on_message_expiration    = true
  max_size_in_megabytes                   = 1024
}

# Eventos BlobCreated entregados por Event Grid (variante B)
resource "azurerm_servicebus_queue" "eventos_blob" {
  name         = "eventos-blob"
  namespace_id = azurerm_servicebus_namespace.sb.id

  lock_duration                        = "PT5M"
  max_delivery_count                   = 5
  default_message_ttl                  = "P7D"
  dead_lettering_on_message_expiration = true
}

# ---------------------------------------------------------------- Event Grid (variante B)
resource "azurerm_eventgrid_system_topic" "storage" {
  name                = "evgt-storage-cc"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  source_resource_id  = azurerm_storage_account.st.id
  topic_type          = "Microsoft.Storage.StorageAccounts"

  identity {
    type = "SystemAssigned"
  }
}

# El tópico entrega a la cola con SU identidad: necesita poder enviar
resource "azurerm_role_assignment" "eventgrid_envia" {
  scope                = azurerm_servicebus_queue.eventos_blob.id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = azurerm_eventgrid_system_topic.storage.identity[0].principal_id
}

resource "azurerm_eventgrid_system_topic_event_subscription" "blob_creado" {
  name                  = "blobcreated-a-cola"
  system_topic          = azurerm_eventgrid_system_topic.storage.name
  resource_group_name   = azurerm_resource_group.rg.name
  event_delivery_schema = "CloudEventSchemaV1_0"

  included_event_types = ["Microsoft.Storage.BlobCreated"]

  subject_filter {
    subject_begins_with = "/blobServices/default/containers/subidas/blobs/usuarios/"
  }

  service_bus_queue_endpoint_id = azurerm_servicebus_queue.eventos_blob.id

  delivery_identity {
    type = "SystemAssigned"
  }

  retry_policy {
    max_delivery_attempts = 10
    event_time_to_live    = 1440 # minutos
  }

  depends_on = [azurerm_role_assignment.eventgrid_envia]
}

# ---------------------------------------------------------------- Roles de las aplicaciones
# Productor: escribe en su contenedor y publica en la cola de tickets
resource "azurerm_role_assignment" "productor_blob" {
  scope                = "${azurerm_storage_account.st.id}/blobServices/default/containers/${azurerm_storage_container.subidas.name}"
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.principal_productor
}

resource "azurerm_role_assignment" "productor_sb" {
  scope                = azurerm_servicebus_queue.archivos.id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = var.principal_productor
}

# Consumidor: recibe tickets y eventos, lee blobs y marca el estado (etiquetas => Contributor)
resource "azurerm_role_assignment" "consumidor_blob" {
  scope                = "${azurerm_storage_account.st.id}/blobServices/default/containers/${azurerm_storage_container.subidas.name}"
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.principal_consumidor
}

resource "azurerm_role_assignment" "consumidor_archivos" {
  scope                = azurerm_servicebus_queue.archivos.id
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = var.principal_consumidor
}

resource "azurerm_role_assignment" "consumidor_eventos" {
  scope                = azurerm_servicebus_queue.eventos_blob.id
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = var.principal_consumidor
}

output "cuenta" {
  value = azurerm_storage_account.st.name
}

output "namespace" {
  value = "${azurerm_servicebus_namespace.sb.name}.servicebus.windows.net"
}
