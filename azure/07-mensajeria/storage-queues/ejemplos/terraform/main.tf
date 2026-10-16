# Storage Queues listo para producción (versión de estudio):
#   - Cuenta de Storage sin claves (solo Entra ID), TLS 1.2, ZRS
#   - Colas "tareas" y "tareas-poison" (la de veneno la alimenta tu código o las Functions)
#   - Roles mínimos por cola: productor (enviar) y trabajador (procesar mensajes)
#   - Red privada opcional (Private Endpoint subrecurso "queue")
#   - Diagnóstico del servicio de colas a Log Analytics y alerta de errores/limitación
#     (la cola de veneno se vigila con una consulta o métrica propia: ver ejemplos/kql)
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

variable "red_privada" {
  description = "true: sin acceso público; la cuenta se alcanza por Private Endpoint"
  type        = bool
  default     = false
}

variable "principal_productor" {
  type    = string
  default = "00000000-0000-0000-0000-000000000001"
}

variable "principal_trabajador" {
  type    = string
  default = "00000000-0000-0000-0000-000000000002"
}

variable "correo_alertas" {
  type    = string
  default = "operaciones@modalima.example"
}

resource "random_string" "sufijo" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-estudio-storagequeues"
  location = var.ubicacion
}

# ---------------------------------------------------------------- Cuenta de Storage
resource "azurerm_storage_account" "colas" {
  name                            = "stqmodalima${random_string.sufijo.result}"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  account_tier                    = "Standard"
  account_replication_type        = "ZRS"
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false # solo Entra ID
  default_to_oauth_authentication = true
  public_network_access_enabled   = !var.red_privada
}

# ---------------------------------------------------------------- Colas
resource "azurerm_storage_queue" "tareas" {
  name               = "tareas"
  storage_account_id = azurerm_storage_account.colas.id
}

# Cola de veneno: aquí caen los mensajes que superaron los intentos (alerta si no está vacía)
resource "azurerm_storage_queue" "veneno" {
  name               = "tareas-poison"
  storage_account_id = azurerm_storage_account.colas.id
}

# ---------------------------------------------------------------- Roles por cola
resource "azurerm_role_assignment" "productor" {
  scope                = azurerm_storage_account.colas.id # los roles de datos de cola se asignan en la cuenta o el contenedor de colas
  role_definition_name = "Storage Queue Data Message Sender"
  principal_id         = var.principal_productor
}

resource "azurerm_role_assignment" "trabajador" {
  scope                = azurerm_storage_account.colas.id
  role_definition_name = "Storage Queue Data Message Processor"
  principal_id         = var.principal_trabajador
}

# El trabajador también envía a la cola de veneno
resource "azurerm_role_assignment" "trabajador_envia_veneno" {
  scope                = azurerm_storage_account.colas.id
  role_definition_name = "Storage Queue Data Message Sender"
  principal_id         = var.principal_trabajador
}

# ---------------------------------------------------------------- Red privada
resource "azurerm_virtual_network" "vnet" {
  count               = var.red_privada ? 1 : 0
  name                = "vnet-colas"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  address_space       = ["10.62.0.0/16"]
}

resource "azurerm_subnet" "privado" {
  count                = var.red_privada ? 1 : 0
  name                 = "snet-private-endpoints"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet[0].name
  address_prefixes     = ["10.62.2.0/24"]
}

resource "azurerm_private_dns_zone" "cola" {
  count               = var.red_privada ? 1 : 0
  name                = "privatelink.queue.core.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "cola" {
  count                 = var.red_privada ? 1 : 0
  name                  = "enlace-colas"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.cola[0].name
  virtual_network_id    = azurerm_virtual_network.vnet[0].id
}

resource "azurerm_private_endpoint" "cola" {
  count               = var.red_privada ? 1 : 0
  name                = "pe-colas"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  subnet_id           = azurerm_subnet.privado[0].id

  private_service_connection {
    name                           = "psc-colas"
    private_connection_resource_id = azurerm_storage_account.colas.id
    subresource_names              = ["queue"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-colas"
    private_dns_zone_ids = [azurerm_private_dns_zone.cola[0].id]
  }
}

# ---------------------------------------------------------------- Observabilidad
resource "azurerm_log_analytics_workspace" "log" {
  name                = "log-colas-${random_string.sufijo.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# Los registros y métricas de las colas se configuran en el servicio "queueServices/default" de la cuenta
resource "azurerm_monitor_diagnostic_setting" "cola" {
  name                       = "diag-colas"
  target_resource_id         = "${azurerm_storage_account.colas.id}/queueServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log.id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "Transaction"
  }

  enabled_metric {
    category = "Capacity"
  }
}

resource "azurerm_monitor_action_group" "operaciones" {
  name                = "ag-operaciones-colas"
  resource_group_name = azurerm_resource_group.rg.name
  short_name          = "opscol"

  email_receiver {
    name          = "equipo"
    email_address = var.correo_alertas
  }
}

# Cualquier mensaje en la cola de veneno debe enterarle a alguien.
# La métrica QueueMessageCount es del servicio de colas y se evalúa por cola con KQL (ver ejemplos/kql);
# aquí se alerta por volumen de errores de transacción en el servicio.
resource "azurerm_monitor_metric_alert" "errores" {
  name                = "alerta-colas-errores"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = ["${azurerm_storage_account.colas.id}/queueServices/default"]
  description         = "Errores de servidor o limitación en las colas"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Storage/storageAccounts/queueServices"
    metric_name      = "Transactions"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 1000

    dimension {
      name     = "ResponseType"
      operator = "Include"
      values   = ["ServerBusyError", "ServerTimeoutError", "ClientThrottlingError"]
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.operaciones.id
  }
}

output "endpoint_colas" {
  value = azurerm_storage_account.colas.primary_queue_endpoint
}

output "cuenta" {
  value = azurerm_storage_account.colas.name
}
