# Event Hubs listo para producción (versión de estudio):
#   - Namespace sin claves (solo Entra ID), TLS 1.2, auto-inflate acotado
#   - Event hubs: clics-web (8 particiones + Capture a Data Lake/Blob), pedidos-cdc, errores-clics (DLQ manual)
#   - Un grupo de consumidores por microservicio + grupo "reproceso" para reproducir sin tocar a los demás
#   - Registro de esquemas (grupo con compatibilidad Backward)
#   - Storage para checkpoints (SDK nativo) y para Capture, con roles mínimos
#   - Red privada opcional (Private Endpoint + zona privatelink.servicebus.windows.net)
#   - Diagnóstico a Log Analytics y alertas de limitación, errores de servidor y backlog de Capture
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

variable "sku" {
  description = "Standard (Kafka, Capture, Schema Registry) o Premium (aislado, más retención y funciones Kafka)"
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.sku)
    error_message = "sku debe ser Standard o Premium."
  }
}

variable "capacidad" {
  description = "Unidades de rendimiento (Standard) o de procesamiento (Premium)"
  type        = number
  default     = 2
}

variable "maximo_tu" {
  description = "Tope del auto-inflate (solo Standard); 0 lo desactiva"
  type        = number
  default     = 6
}

variable "red_privada" {
  description = "true: sin acceso público; el namespace se alcanza por Private Endpoint"
  type        = bool
  default     = false
}

variable "principal_productor" {
  description = "Object id de la identidad que publica"
  type        = string
  default     = "00000000-0000-0000-0000-000000000001"
}

variable "principal_consumidor" {
  description = "Object id de la identidad que consume"
  type        = string
  default     = "00000000-0000-0000-0000-000000000002"
}

variable "correo_alertas" {
  type    = string
  default = "operaciones@modalima.example"
}

locals {
  standard = var.sku == "Standard"
  grupos   = ["analitica", "antifraude", "busqueda", "reproceso"]
}

resource "random_string" "sufijo" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-estudio-eventhubs"
  location = var.ubicacion
}

# ---------------------------------------------------------------- Namespace
resource "azurerm_eventhub_namespace" "eh" {
  name                = "evhns-modalima-${random_string.sufijo.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = var.sku
  capacity            = var.capacidad

  auto_inflate_enabled     = local.standard && var.maximo_tu > 0 # sube TU solo; no baja solo
  maximum_throughput_units = local.standard && var.maximo_tu > 0 ? var.maximo_tu : null

  local_authentication_enabled  = false # sin SAS: solo Entra ID (para Kafka usa OAUTHBEARER)
  minimum_tls_version           = "1.2"
  public_network_access_enabled = !var.red_privada

  identity {
    type = "SystemAssigned" # la usa Capture para escribir en Storage
  }

  # Con red privada: cerrado por defecto; los servicios de confianza (Capture, Event Grid) pueden entrar.
  # (En azurerm 4.x esto se escribe como atributo, no como bloque.)
  network_rulesets = var.red_privada ? [{
    default_action                 = "Deny"
    public_network_access_enabled  = false
    trusted_service_access_enabled = true
    ip_rule                        = []
    virtual_network_rule           = []
  }] : null
}

# ---------------------------------------------------------------- Storage: checkpoints y Capture
resource "azurerm_storage_account" "datos" {
  name                            = "stehmodalima${random_string.sufijo.result}"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  account_tier                    = "Standard"
  account_replication_type        = "ZRS"
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false # solo Entra ID, también para los checkpoints
  default_to_oauth_authentication = true
  public_network_access_enabled   = !var.red_privada
}

resource "azurerm_storage_container" "checkpoints" {
  name                  = "checkpoints"
  storage_account_id    = azurerm_storage_account.datos.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "capture" {
  name                  = "capture-clics"
  storage_account_id    = azurerm_storage_account.datos.id
  container_access_type = "private"
}

# Capture escribe con la identidad del namespace
resource "azurerm_role_assignment" "capture_escribe" {
  scope                = azurerm_storage_container.capture.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_eventhub_namespace.eh.identity[0].principal_id
}

# ---------------------------------------------------------------- Event hubs (= topics de Kafka)
resource "azurerm_eventhub" "clics" {
  name              = "clics-web"
  namespace_id      = azurerm_eventhub_namespace.eh.id
  partition_count   = 8 # = paralelismo máximo de lectura por grupo (Standard: no se cambia después)
  message_retention = 3 # días (Standard: 1 a 7)

  capture_description {
    enabled             = true
    encoding            = "Avro"
    interval_in_seconds = 300       # cada 5 minutos...
    size_limit_in_bytes = 314572800 # ...o cada 300 MB, lo que ocurra primero
    skip_empty_archives = true

    destination {
      name                        = "EventHubArchive.AzureBlockBlob"
      archive_name_format         = "{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}"
      blob_container_name         = azurerm_storage_container.capture.name
      storage_account_id          = azurerm_storage_account.datos.id
      storage_authentication_type = "SystemAssigned" # Capture escribe con la identidad del namespace (verifica valores en la doc del proveedor)
    }
  }

  depends_on = [azurerm_role_assignment.capture_escribe]
}

resource "azurerm_eventhub" "cdc" {
  name              = "pedidos-cdc"
  namespace_id      = azurerm_eventhub_namespace.eh.id
  partition_count   = 4
  message_retention = 7
}

# DLQ manual: aquí van los eventos venenosos con su motivo
resource "azurerm_eventhub" "errores" {
  name              = "errores-clics"
  namespace_id      = azurerm_eventhub_namespace.eh.id
  partition_count   = 2
  message_retention = 7
}

# Un grupo por microservicio (y uno para reproducir sin tocar a los demás)
resource "azurerm_eventhub_consumer_group" "grupos" {
  for_each = toset(local.grupos)

  name                = each.value
  namespace_name      = azurerm_eventhub_namespace.eh.name
  eventhub_name       = azurerm_eventhub.clics.name
  resource_group_name = azurerm_resource_group.rg.name
}

# ---------------------------------------------------------------- Registro de esquemas
resource "azurerm_eventhub_namespace_schema_group" "modalima" {
  name                 = "modalima"
  namespace_id         = azurerm_eventhub_namespace.eh.id
  schema_compatibility = "Backward"
  schema_type          = "Avro"
}

# ---------------------------------------------------------------- Roles por event hub (mínimo privilegio)
resource "azurerm_role_assignment" "productor_clics" {
  scope                = azurerm_eventhub.clics.id
  role_definition_name = "Azure Event Hubs Data Sender"
  principal_id         = var.principal_productor
}

resource "azurerm_role_assignment" "productor_errores" {
  scope                = azurerm_eventhub.errores.id
  role_definition_name = "Azure Event Hubs Data Sender"
  principal_id         = var.principal_consumidor # el consumidor publica sus venenosos
}

resource "azurerm_role_assignment" "consumidor_clics" {
  scope                = azurerm_eventhub.clics.id
  role_definition_name = "Azure Event Hubs Data Receiver"
  principal_id         = var.principal_consumidor
}

# Solo con SDK nativo: el consumidor escribe sus checkpoints en el contenedor
resource "azurerm_role_assignment" "consumidor_checkpoints" {
  scope                = azurerm_storage_container.checkpoints.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.principal_consumidor
}

# ---------------------------------------------------------------- Red privada
resource "azurerm_virtual_network" "vnet" {
  count               = var.red_privada ? 1 : 0
  name                = "vnet-eventhubs"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  address_space       = ["10.61.0.0/16"]
}

resource "azurerm_subnet" "privado" {
  count                = var.red_privada ? 1 : 0
  name                 = "snet-private-endpoints"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet[0].name
  address_prefixes     = ["10.61.2.0/24"]
}

# Event Hubs comparte la zona privatelink.servicebus.windows.net con Service Bus
resource "azurerm_private_dns_zone" "eh" {
  count               = var.red_privada ? 1 : 0
  name                = "privatelink.servicebus.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "eh" {
  count                 = var.red_privada ? 1 : 0
  name                  = "enlace-eventhubs"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.eh[0].name
  virtual_network_id    = azurerm_virtual_network.vnet[0].id
}

resource "azurerm_private_endpoint" "eh" {
  count               = var.red_privada ? 1 : 0
  name                = "pe-eventhubs"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  subnet_id           = azurerm_subnet.privado[0].id

  private_service_connection {
    name                           = "psc-eventhubs"
    private_connection_resource_id = azurerm_eventhub_namespace.eh.id
    subresource_names              = ["namespace"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-eventhubs"
    private_dns_zone_ids = [azurerm_private_dns_zone.eh[0].id]
  }
}

# ---------------------------------------------------------------- Observabilidad
resource "azurerm_log_analytics_workspace" "log" {
  name                = "log-eventhubs-${random_string.sufijo.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_monitor_diagnostic_setting" "eh" {
  name                       = "diag-eventhubs"
  target_resource_id         = azurerm_eventhub_namespace.eh.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log.id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_action_group" "operaciones" {
  name                = "ag-operaciones-eh"
  resource_group_name = azurerm_resource_group.rg.name
  short_name          = "opseh"

  email_receiver {
    name          = "equipo"
    email_address = var.correo_alertas
  }
}

# Limitación: la capacidad se quedó corta (o el auto-inflate llegó a su tope)
resource "azurerm_monitor_metric_alert" "limitacion" {
  name                = "alerta-eh-limitacion"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_eventhub_namespace.eh.id]
  description         = "Solicitudes limitadas por exceso de capacidad"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.EventHub/namespaces"
    metric_name      = "ThrottledRequests"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0
  }

  action {
    action_group_id = azurerm_monitor_action_group.operaciones.id
  }
}

resource "azurerm_monitor_metric_alert" "errores_servidor" {
  name                = "alerta-eh-errores-servidor"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_eventhub_namespace.eh.id]
  description         = "Errores del lado del servicio"
  severity            = 1
  frequency           = "PT5M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.EventHub/namespaces"
    metric_name      = "ServerErrors"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0
  }

  action {
    action_group_id = azurerm_monitor_action_group.operaciones.id
  }
}

# Capture atrasado = archivos que no llegan al lago
resource "azurerm_monitor_metric_alert" "capture_atrasado" {
  name                = "alerta-eh-capture-backlog"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_eventhub_namespace.eh.id]
  description         = "Capture acumula bytes sin escribir"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.EventHub/namespaces"
    metric_name      = "CaptureBacklog"
    aggregation      = "Maximum"
    operator         = "GreaterThan"
    threshold        = 1000000
  }

  action {
    action_group_id = azurerm_monitor_action_group.operaciones.id
  }
}

output "namespace" {
  value = "${azurerm_eventhub_namespace.eh.name}.servicebus.windows.net"
}

output "bootstrap_kafka" {
  value = "${azurerm_eventhub_namespace.eh.name}.servicebus.windows.net:9093"
}

output "cuenta_checkpoints" {
  value = azurerm_storage_account.datos.primary_blob_endpoint
}

output "workspace_logs" {
  value = azurerm_log_analytics_workspace.log.id
}
