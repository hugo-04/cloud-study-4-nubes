# Eventos de Blob con Event Grid: tópico del sistema + 3 suscripciones con destinos distintos.
#   1) Cola de Service Bus (lo normal para procesar), entrega con identidad, CloudEvents, filtros y dead-letter
#   2) Storage Queue (barato y simple), con filtro avanzado por tamaño y extensión
#   3) Webhook opcional (solo si defines var.webhook_url: Event Grid valida el endpoint al crearla)
# Diagnóstico a Log Analytics para ver fallos de entrega.
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

variable "webhook_url" {
  description = "URL HTTPS del webhook (con ?clave=...). Vacío = no se crea esa suscripción"
  type        = string
  default     = ""
}

variable "app_entra_id" {
  description = "Application (client) ID o URI de la app registrada para autenticar el webhook con Entra ID (opcional)"
  type        = string
  default     = ""
}

resource "random_string" "sufijo" {
  length  = 6
  upper   = false
  special = false
}

data "azurerm_client_config" "actual" {}

resource "azurerm_resource_group" "rg" {
  name     = "rg-estudio-eventos-blob"
  location = var.ubicacion
}

# ---------------------------------------------------------------- Fuente: cuenta de storage
resource "azurerm_storage_account" "st" {
  name                            = "stev${random_string.sufijo.result}"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  account_tier                    = "Standard"
  account_replication_type        = "ZRS"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false

  blob_properties {
    delete_retention_policy {
      days = 7
    }
    change_feed_enabled = true # registro durable para auditoría (los eventos NO lo reemplazan)
  }
}

# Entrada y salida SEPARADAS: evita el bucle "el resultado dispara otro evento"
resource "azurerm_storage_container" "subidas" {
  name                  = "subidas"
  storage_account_id    = azurerm_storage_account.st.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "resultados" {
  name                  = "resultados"
  storage_account_id    = azurerm_storage_account.st.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "deadletter" {
  name                  = "deadletter"
  storage_account_id    = azurerm_storage_account.st.id
  container_access_type = "private"
}

resource "azurerm_storage_queue" "eventos" {
  name                 = "eventos-blob"
  storage_account_name = azurerm_storage_account.st.name
}

# ---------------------------------------------------------------- Destino 1: Service Bus
resource "azurerm_servicebus_namespace" "sb" {
  name                = "sb-ev-${random_string.sufijo.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Standard"
  local_auth_enabled  = false
  minimum_tls_version = "1.2"
}

resource "azurerm_servicebus_queue" "eventos" {
  name                                 = "eventos-blob"
  namespace_id                         = azurerm_servicebus_namespace.sb.id
  lock_duration                        = "PT5M"
  max_delivery_count                   = 5
  default_message_ttl                  = "P7D"
  dead_lettering_on_message_expiration = true
}

# ---------------------------------------------------------------- Tópico del sistema (uno por cuenta)
resource "azurerm_eventgrid_system_topic" "storage" {
  name                = "evgt-${azurerm_storage_account.st.name}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  source_resource_id  = azurerm_storage_account.st.id
  topic_type          = "Microsoft.Storage.StorageAccounts"

  identity {
    type = "SystemAssigned"
  }
}

# Permisos de la identidad DEL TÓPICO en cada destino (mínimo privilegio)
resource "azurerm_role_assignment" "a_service_bus" {
  scope                = azurerm_servicebus_queue.eventos.id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = azurerm_eventgrid_system_topic.storage.identity[0].principal_id
}

resource "azurerm_role_assignment" "a_storage_queue" {
  scope                = azurerm_storage_account.st.id
  role_definition_name = "Storage Queue Data Message Sender"
  principal_id         = azurerm_eventgrid_system_topic.storage.identity[0].principal_id
}

resource "azurerm_role_assignment" "al_deadletter" {
  scope                = "${azurerm_storage_account.st.id}/blobServices/default/containers/${azurerm_storage_container.deadletter.name}"
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_eventgrid_system_topic.storage.identity[0].principal_id
}

# ---------------------------------------------------------------- Suscripción 1: BlobCreated -> Service Bus
resource "azurerm_eventgrid_system_topic_event_subscription" "a_cola_sb" {
  name                  = "blobcreated-a-servicebus"
  system_topic          = azurerm_eventgrid_system_topic.storage.name
  resource_group_name   = azurerm_resource_group.rg.name
  event_delivery_schema = "CloudEventSchemaV1_0"

  included_event_types = ["Microsoft.Storage.BlobCreated"]

  subject_filter {
    subject_begins_with = "/blobServices/default/containers/subidas/blobs/entrada/"
    case_sensitive      = true
  }

  # Solo subidas completas por las operaciones esperadas y no vacías
  advanced_filter {
    string_in {
      key    = "data.api"
      values = ["PutBlob", "PutBlockList", "FlushWithClose", "SftpCommit"]
    }
    number_greater_than {
      key   = "data.contentLength"
      value = 0
    }
  }

  service_bus_queue_endpoint_id = azurerm_servicebus_queue.eventos.id

  delivery_identity {
    type = "SystemAssigned"
  }

  retry_policy {
    max_delivery_attempts = 30
    event_time_to_live    = 1440 # minutos
  }

  storage_blob_dead_letter_destination {
    storage_account_id          = azurerm_storage_account.st.id
    storage_blob_container_name = azurerm_storage_container.deadletter.name
  }

  dead_letter_identity {
    type = "SystemAssigned"
  }

  depends_on = [
    azurerm_role_assignment.a_service_bus,
    azurerm_role_assignment.al_deadletter,
  ]
}

# ---------------------------------------------------------------- Suscripción 2: CSV grandes -> Storage Queue
resource "azurerm_eventgrid_system_topic_event_subscription" "a_storage_queue" {
  name                  = "csv-a-storage-queue"
  system_topic          = azurerm_eventgrid_system_topic.storage.name
  resource_group_name   = azurerm_resource_group.rg.name
  event_delivery_schema = "EventGridSchema"

  included_event_types = ["Microsoft.Storage.BlobCreated"]

  subject_filter {
    subject_begins_with = "/blobServices/default/containers/subidas/blobs/csv/"
    subject_ends_with   = ".csv"
  }

  advanced_filter {
    number_greater_than {
      key   = "data.contentLength"
      value = 1024
    }
  }

  storage_queue_endpoint {
    storage_account_id                    = azurerm_storage_account.st.id
    queue_name                            = azurerm_storage_queue.eventos.name
    queue_message_time_to_live_in_seconds = 604800
  }

  delivery_identity {
    type = "SystemAssigned"
  }

  depends_on = [azurerm_role_assignment.a_storage_queue]
}

# ---------------------------------------------------------------- Suscripción 3: webhook (opcional)
resource "azurerm_eventgrid_system_topic_event_subscription" "webhook" {
  count = var.webhook_url == "" ? 0 : 1

  name                  = "blobcreated-webhook"
  system_topic          = azurerm_eventgrid_system_topic.storage.name
  resource_group_name   = azurerm_resource_group.rg.name
  event_delivery_schema = "EventGridSchema"

  included_event_types = ["Microsoft.Storage.BlobCreated", "Microsoft.Storage.BlobDeleted"]

  subject_filter {
    subject_begins_with = "/blobServices/default/containers/subidas/blobs/"
  }

  webhook_endpoint {
    url                               = var.webhook_url
    max_events_per_batch              = 10
    preferred_batch_size_in_kilobytes = 64
    active_directory_tenant_id        = var.app_entra_id == "" ? null : data.azurerm_client_config.actual.tenant_id
    active_directory_app_id_or_uri    = var.app_entra_id == "" ? null : var.app_entra_id
  }

  retry_policy {
    max_delivery_attempts = 10
    event_time_to_live    = 120
  }
}

# ---------------------------------------------------------------- Diagnóstico: fallos de entrega a Log Analytics
resource "azurerm_log_analytics_workspace" "log" {
  name                = "log-eventos-blob-${random_string.sufijo.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_monitor_diagnostic_setting" "topico" {
  name                       = "diag-topico"
  target_resource_id         = azurerm_eventgrid_system_topic.storage.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log.id

  enabled_log {
    category = "DeliveryFailures"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

output "cuenta" {
  value = azurerm_storage_account.st.name
}

output "topico_sistema" {
  value = azurerm_eventgrid_system_topic.storage.name
}
