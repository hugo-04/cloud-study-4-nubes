# Service Bus listo para producción (versión de estudio):
#   - Namespace sin claves (solo Entra ID), TLS 1.2; Standard por defecto, Premium con red privada si lo pides
#   - Cola "pedidos" (duplicados, DLQ por expiración, entregas máximas), cola con sesiones, cola de facturas
#   - Tópico "eventos-pedido" con 3 suscripciones: filtro de correlación, filtro SQL y "todo" con auto-forward
#   - Roles mínimos por entidad
#   - Diagnóstico a Log Analytics y alerta cuando aparece algo en la DLQ
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
  description = "Standard (colas y tópicos) o Premium (dedicado, red privada, mensajes grandes)"
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.sku)
    error_message = "sku debe ser Standard o Premium."
  }
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
  premium = var.sku == "Premium"
}

resource "random_string" "sufijo" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-estudio-servicebus"
  location = var.ubicacion
}

# ---------------------------------------------------------------- Namespace
resource "azurerm_servicebus_namespace" "sb" {
  name                = "sb-modalima-${random_string.sufijo.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = var.sku

  capacity                     = local.premium ? 1 : 0 # unidades de mensajería (solo Premium)
  premium_messaging_partitions = local.premium ? 1 : 0

  local_auth_enabled            = false # sin SharedAccessKey: solo Entra ID
  minimum_tls_version           = "1.2"
  public_network_access_enabled = !local.premium # Premium: se accede por Private Endpoint

  # Reglas de red (solo Premium): cerrado por defecto; los servicios de confianza (Event Grid, etc.) pueden entrar
  dynamic "network_rule_set" {
    for_each = local.premium ? [1] : []
    content {
      default_action                = "Deny"
      public_network_access_enabled = false
      trusted_services_allowed      = true
    }
  }
}

# ---------------------------------------------------------------- Colas
resource "azurerm_servicebus_queue" "pedidos" {
  name         = "pedidos"
  namespace_id = azurerm_servicebus_namespace.sb.id

  lock_duration                           = "PT1M"
  max_delivery_count                      = 8      # tras 8 entregas -> DLQ
  default_message_ttl                     = "P14D" # lo viejo ya no sirve
  dead_lettering_on_message_expiration    = true   # lo vencido va a la DLQ, no desaparece
  requires_duplicate_detection            = true   # mismo MessageId en la ventana = descartado
  duplicate_detection_history_time_window = "PT10M"
  max_size_in_megabytes                   = 5120
}

# Orden FIFO por clave (SessionId = cliente)
resource "azurerm_servicebus_queue" "pedidos_ordenados" {
  name                  = "pedidos-ordenados"
  namespace_id          = azurerm_servicebus_namespace.sb.id
  requires_session      = true
  lock_duration         = "PT1M"
  max_delivery_count    = 8
  default_message_ttl   = "P14D"
  max_size_in_megabytes = 5120

  dead_lettering_on_message_expiration = true
}

resource "azurerm_servicebus_queue" "facturas" {
  name                                 = "facturas"
  namespace_id                         = azurerm_servicebus_namespace.sb.id
  lock_duration                        = "PT2M"
  max_delivery_count                   = 5
  default_message_ttl                  = "P7D"
  dead_lettering_on_message_expiration = true
}

resource "azurerm_servicebus_queue" "auditoria" {
  name                = "auditoria"
  namespace_id        = azurerm_servicebus_namespace.sb.id
  default_message_ttl = "P30D"
}

# ---------------------------------------------------------------- Tópico y suscripciones (solo Standard/Premium)
resource "azurerm_servicebus_topic" "eventos_pedido" {
  name                         = "eventos-pedido"
  namespace_id                 = azurerm_servicebus_namespace.sb.id
  default_message_ttl          = "P7D"
  requires_duplicate_detection = true
}

resource "azurerm_servicebus_subscription" "facturacion" {
  name                                      = "facturacion"
  topic_id                                  = azurerm_servicebus_topic.eventos_pedido.id
  max_delivery_count                        = 8
  lock_duration                             = "PT1M"
  dead_lettering_on_message_expiration      = true
  dead_lettering_on_filter_evaluation_error = true
}

# Solo los eventos con Subject = "pedido.pagado". Se llama $Default para REEMPLAZAR el filtro "todo" que crea el servicio.
# Si tu versión del proveedor no adopta $Default, bórrala con: az servicebus topic subscription rule delete ... -n '$Default'
# y deja una regla con nombre propio (de lo contrario la suscripción recibe TODO: las reglas se combinan con OR).
resource "azurerm_servicebus_subscription_rule" "facturacion_pagados" {
  name            = "$Default"
  subscription_id = azurerm_servicebus_subscription.facturacion.id
  filter_type     = "CorrelationFilter"

  correlation_filter {
    label = "pedido.pagado"
  }
}

resource "azurerm_servicebus_subscription" "inventario" {
  name               = "inventario"
  topic_id           = azurerm_servicebus_topic.eventos_pedido.id
  max_delivery_count = 8
  lock_duration      = "PT1M"
}

# Filtro SQL sobre propiedades de aplicación (más flexible, más costoso que correlación)
resource "azurerm_servicebus_subscription_rule" "inventario_peru" {
  name            = "$Default"
  subscription_id = azurerm_servicebus_subscription.inventario.id
  filter_type     = "SqlFilter"
  sql_filter      = "region = 'PE' AND total > 100"
}

# Recibe todo y lo reenvía automáticamente a una cola (auto-forward)
resource "azurerm_servicebus_subscription" "auditoria" {
  name               = "auditoria"
  topic_id           = azurerm_servicebus_topic.eventos_pedido.id
  max_delivery_count = 10
  forward_to         = azurerm_servicebus_queue.auditoria.name
}

# ---------------------------------------------------------------- Roles por entidad (mínimo privilegio)
resource "azurerm_role_assignment" "productor_cola" {
  scope                = azurerm_servicebus_queue.pedidos.id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = var.principal_productor
}

resource "azurerm_role_assignment" "productor_topico" {
  scope                = azurerm_servicebus_topic.eventos_pedido.id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = var.principal_productor
}

resource "azurerm_role_assignment" "consumidor_cola" {
  scope                = azurerm_servicebus_queue.pedidos.id
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = var.principal_consumidor
}

resource "azurerm_role_assignment" "consumidor_facturacion" {
  scope                = azurerm_servicebus_subscription.facturacion.id
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = var.principal_consumidor
}

# ---------------------------------------------------------------- Premium: red privada
resource "azurerm_virtual_network" "vnet" {
  count               = local.premium ? 1 : 0
  name                = "vnet-servicebus"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  address_space       = ["10.60.0.0/16"]
}

resource "azurerm_subnet" "privado" {
  count                = local.premium ? 1 : 0
  name                 = "snet-private-endpoints"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet[0].name
  address_prefixes     = ["10.60.2.0/24"]
}

resource "azurerm_private_dns_zone" "sb" {
  count               = local.premium ? 1 : 0
  name                = "privatelink.servicebus.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "sb" {
  count                 = local.premium ? 1 : 0
  name                  = "enlace-servicebus"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.sb[0].name
  virtual_network_id    = azurerm_virtual_network.vnet[0].id
}

resource "azurerm_private_endpoint" "sb" {
  count               = local.premium ? 1 : 0
  name                = "pe-servicebus"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  subnet_id           = azurerm_subnet.privado[0].id

  private_service_connection {
    name                           = "psc-servicebus"
    private_connection_resource_id = azurerm_servicebus_namespace.sb.id
    subresource_names              = ["namespace"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-servicebus"
    private_dns_zone_ids = [azurerm_private_dns_zone.sb[0].id]
  }
}

# ---------------------------------------------------------------- Observabilidad
resource "azurerm_log_analytics_workspace" "log" {
  name                = "log-servicebus-${random_string.sufijo.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_monitor_diagnostic_setting" "sb" {
  name                       = "diag-servicebus"
  target_resource_id         = azurerm_servicebus_namespace.sb.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log.id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_action_group" "operaciones" {
  name                = "ag-operaciones"
  resource_group_name = azurerm_resource_group.rg.name
  short_name          = "ops"

  email_receiver {
    name          = "equipo"
    email_address = var.correo_alertas
  }
}

# Cualquier mensaje en una DLQ debe enterarle a alguien
resource "azurerm_monitor_metric_alert" "dlq" {
  name                = "alerta-dlq"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_servicebus_namespace.sb.id]
  description         = "Hay mensajes en la cola de mensajes fallidos"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.ServiceBus/namespaces"
    metric_name      = "DeadletteredMessages"
    aggregation      = "Maximum"
    operator         = "GreaterThan"
    threshold        = 0
  }

  action {
    action_group_id = azurerm_monitor_action_group.operaciones.id
  }
}

output "namespace" {
  value = "${azurerm_servicebus_namespace.sb.name}.servicebus.windows.net"
}
