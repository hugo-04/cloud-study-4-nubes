# Event Grid completo (versión de estudio):
#   1) Tópico personalizado (CloudEvents, sin claves) -> suscripción a Service Bus con filtros, identidad y dead-letter
#   2) Dominio multi-cliente con un tópico hijo por cliente
#   3) Tópico del sistema de Key Vault: secretos por vencer / vencidos -> cola de Service Bus
#   4) Espacio de nombres con tópico (entrega pull); las suscripciones pull se crean con la CLI
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

variable "principal_publicador" {
  description = "Object id de la identidad que publica eventos"
  type        = string
  default     = "00000000-0000-0000-0000-000000000001"
}

variable "principal_consumidor_pull" {
  description = "Object id de la identidad que consume del namespace por pull"
  type        = string
  default     = "00000000-0000-0000-0000-000000000002"
}

data "azurerm_client_config" "actual" {}

resource "random_string" "sufijo" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-estudio-eventgrid"
  location = var.ubicacion
}

# ---------------------------------------------------------------- Destinos: Service Bus y dead-letter
resource "azurerm_servicebus_namespace" "sb" {
  name                = "sb-eg-${random_string.sufijo.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Standard"
  local_auth_enabled  = false
  minimum_tls_version = "1.2"
}

resource "azurerm_servicebus_queue" "pedidos" {
  name                                 = "pedidos-eventos"
  namespace_id                         = azurerm_servicebus_namespace.sb.id
  max_delivery_count                   = 8
  dead_lettering_on_message_expiration = true
}

resource "azurerm_servicebus_queue" "kv" {
  name                                 = "kv-eventos"
  namespace_id                         = azurerm_servicebus_namespace.sb.id
  max_delivery_count                   = 5
  dead_lettering_on_message_expiration = true
}

resource "azurerm_storage_account" "dl" {
  name                            = "stegdl${random_string.sufijo.result}"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
}

resource "azurerm_storage_container" "deadletter" {
  name                  = "deadletter-eventos"
  storage_account_id    = azurerm_storage_account.dl.id
  container_access_type = "private"
}

# ---------------------------------------------------------------- 1) Tópico personalizado
resource "azurerm_eventgrid_topic" "pedidos" {
  name                          = "evgt-pedidos-${random_string.sufijo.result}"
  resource_group_name           = azurerm_resource_group.rg.name
  location                      = azurerm_resource_group.rg.location
  input_schema                  = "CloudEventSchemaV1_0"
  local_auth_enabled            = false # solo Entra ID
  public_network_access_enabled = true  # false + Private Endpoint en producción

  identity {
    type = "SystemAssigned"
  }
}

# El publicador necesita 'EventGrid Data Sender' en el tópico
resource "azurerm_role_assignment" "publicador" {
  scope                = azurerm_eventgrid_topic.pedidos.id
  role_definition_name = "EventGrid Data Sender"
  principal_id         = var.principal_publicador
}

# La identidad del tópico entrega a la cola y escribe el dead-letter
resource "azurerm_role_assignment" "topico_a_cola" {
  scope                = azurerm_servicebus_queue.pedidos.id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = azurerm_eventgrid_topic.pedidos.identity[0].principal_id
}

resource "azurerm_role_assignment" "topico_deadletter" {
  scope                = "${azurerm_storage_account.dl.id}/blobServices/default/containers/${azurerm_storage_container.deadletter.name}"
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_eventgrid_topic.pedidos.identity[0].principal_id
}

resource "azurerm_eventgrid_event_subscription" "pedidos_a_cola" {
  name                  = "pedidos-pagados-peru"
  scope                 = azurerm_eventgrid_topic.pedidos.id
  event_delivery_schema = "CloudEventSchemaV1_0"

  included_event_types = ["pe.modalima.pedido.creado", "pe.modalima.pedido.pagado"]

  subject_filter {
    subject_begins_with = "pedidos/PE/"
  }

  advanced_filter {
    number_greater_than {
      key   = "data.total"
      value = 100
    }
  }

  service_bus_queue_endpoint_id = azurerm_servicebus_queue.pedidos.id

  delivery_identity {
    type = "SystemAssigned"
  }

  retry_policy {
    max_delivery_attempts = 30
    event_time_to_live    = 1440
  }

  storage_blob_dead_letter_destination {
    storage_account_id          = azurerm_storage_account.dl.id
    storage_blob_container_name = azurerm_storage_container.deadletter.name
  }

  dead_letter_identity {
    type = "SystemAssigned"
  }

  depends_on = [
    azurerm_role_assignment.topico_a_cola,
    azurerm_role_assignment.topico_deadletter,
  ]
}

# ---------------------------------------------------------------- 2) Dominio multi-cliente
resource "azurerm_eventgrid_domain" "clientes" {
  name                = "evgd-clientes-${random_string.sufijo.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  input_schema        = "CloudEventSchemaV1_0"

  local_auth_enabled            = false
  public_network_access_enabled = true
}

resource "azurerm_eventgrid_domain_topic" "cliente" {
  for_each            = toset(["cliente-modalima", "cliente-cafeandino"])
  name                = each.key
  domain_name         = azurerm_eventgrid_domain.clientes.name
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_role_assignment" "publicador_dominio" {
  scope                = azurerm_eventgrid_domain.clientes.id
  role_definition_name = "EventGrid Data Sender"
  principal_id         = var.principal_publicador
}

# ---------------------------------------------------------------- 3) Tópico del sistema de Key Vault
resource "azurerm_key_vault" "kv" {
  name                       = "kv-eg-${random_string.sufijo.result}"
  resource_group_name        = azurerm_resource_group.rg.name
  location                   = azurerm_resource_group.rg.location
  tenant_id                  = data.azurerm_client_config.actual.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = false
}

resource "azurerm_eventgrid_system_topic" "kv" {
  name                = "evgt-kv-${random_string.sufijo.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  source_resource_id  = azurerm_key_vault.kv.id
  topic_type          = "Microsoft.KeyVault.vaults"

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_role_assignment" "kv_a_cola" {
  scope                = azurerm_servicebus_queue.kv.id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = azurerm_eventgrid_system_topic.kv.identity[0].principal_id
}

resource "azurerm_eventgrid_system_topic_event_subscription" "kv_vencimientos" {
  name                  = "secretos-por-vencer"
  system_topic          = azurerm_eventgrid_system_topic.kv.name
  resource_group_name   = azurerm_resource_group.rg.name
  event_delivery_schema = "CloudEventSchemaV1_0"

  included_event_types = [
    "Microsoft.KeyVault.SecretNearExpiry",
    "Microsoft.KeyVault.SecretExpired",
  ]

  service_bus_queue_endpoint_id = azurerm_servicebus_queue.kv.id

  delivery_identity {
    type = "SystemAssigned"
  }

  depends_on = [azurerm_role_assignment.kv_a_cola]
}

# ---------------------------------------------------------------- 4) Espacio de nombres con tópico (pull)
resource "azurerm_eventgrid_namespace" "ns" {
  name                = "evgns-modalima-${random_string.sufijo.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Standard"
  capacity            = 1
}

resource "azurerm_eventgrid_namespace_topic" "pedidos" {
  name                    = "pedidos"
  eventgrid_namespace_id  = azurerm_eventgrid_namespace.ns.id
  event_retention_in_days = 3
}

resource "azurerm_role_assignment" "pull_receptor" {
  scope                = azurerm_eventgrid_namespace_topic.pedidos.id
  role_definition_name = "EventGrid Data Receiver"
  principal_id         = var.principal_consumidor_pull
}

resource "azurerm_role_assignment" "pull_emisor" {
  scope                = azurerm_eventgrid_namespace_topic.pedidos.id
  role_definition_name = "EventGrid Data Sender"
  principal_id         = var.principal_publicador
}

output "endpoint_topico" {
  value = azurerm_eventgrid_topic.pedidos.endpoint
}

output "endpoint_dominio" {
  value = azurerm_eventgrid_domain.clientes.endpoint
}

output "endpoint_namespace" {
  value = "https://${azurerm_eventgrid_namespace.ns.name}.${var.ubicacion}-1.eventgrid.azure.net"
}
