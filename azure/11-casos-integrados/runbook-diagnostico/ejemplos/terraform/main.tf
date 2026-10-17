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

variable "grupo_de_recursos" {
  type = string
}

variable "ubicacion" {
  type    = string
  default = "eastus2"
}

variable "workspace_id" {
  description = "ID del espacio de trabajo de Log Analytics donde viven AppRequests y las trazas."
  type        = string
}

variable "namespace_service_bus_id" {
  description = "ID del espacio de nombres de Service Bus de la tienda."
  type        = string
}

variable "correo_guardia" {
  type = string
}

variable "url_runbook" {
  description = "Enlace al runbook que se adjunta a cada alerta."
  type        = string
}

variable "entorno" {
  type    = string
  default = "prod"
}

locals {
  etiquetas = { app = "tienda", env = var.entorno, owner = "equipo-plataforma" }
}

# Quién recibe el aviso
resource "azurerm_monitor_action_group" "guardia" {
  name                = "ag-guardia-tienda-${var.entorno}"
  resource_group_name = var.grupo_de_recursos
  short_name          = "guardia"
  tags                = local.etiquetas

  email_receiver {
    name                    = "correo-guardia"
    email_address           = var.correo_guardia
    use_common_alert_schema = true
  }
}

# Alerta 1: la API devuelve demasiados 5xx (síntoma que ve el cliente)
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "errores_5xx" {
  name                 = "alerta-5xx-tienda-${var.entorno}"
  resource_group_name  = var.grupo_de_recursos
  location             = var.ubicacion
  scopes               = [var.workspace_id]
  severity             = 1
  evaluation_frequency = "PT5M"
  window_duration      = "PT10M"
  description          = "Más del 2 % de solicitudes con 5xx. Runbook: ${var.url_runbook}"
  tags                 = local.etiquetas

  criteria {
    query = <<-KQL
      AppRequests
      | where Name startswith "POST /api/pedidos" or Name startswith "GET /api/"
      | summarize total = count(), errores = countif(toint(ResultCode) >= 500)
      | extend tasa = iff(total == 0, 0.0, todouble(errores) / total)
      | where total > 50 and tasa > 0.02
    KQL

    time_aggregation_method = "Count"
    threshold               = 0
    operator                = "GreaterThan"

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.guardia.id]
  }
}

# Alerta 2: mensajes en la cola de fallidos (el síntoma silencioso)
resource "azurerm_monitor_metric_alert" "dlq" {
  name                = "alerta-dlq-tienda-${var.entorno}"
  resource_group_name = var.grupo_de_recursos
  scopes              = [var.namespace_service_bus_id]
  description         = "Hay mensajes en la cola de fallidos. Runbook: ${var.url_runbook}"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = local.etiquetas

  criteria {
    metric_namespace = "Microsoft.ServiceBus/namespaces"
    metric_name      = "DeadletteredMessages"
    aggregation      = "Maximum"
    operator         = "GreaterThan"
    threshold        = 0
  }

  action {
    action_group_id = azurerm_monitor_action_group.guardia.id
  }
}

# Alerta 3: la sonda sintética informa una dependencia caída (traza estructurada de la aplicación)
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "sonda" {
  name                 = "alerta-sonda-tienda-${var.entorno}"
  resource_group_name  = var.grupo_de_recursos
  location             = var.ubicacion
  scopes               = [var.workspace_id]
  severity             = 2
  evaluation_frequency = "PT5M"
  window_duration      = "PT10M"
  description          = "La sonda no alcanza una dependencia. Runbook: ${var.url_runbook}"
  tags                 = local.etiquetas

  criteria {
    query = <<-KQL
      AppTraces
      | where Message startswith "sonda.dependencia"
      | extend dependencia = tostring(Properties.dependencia), ok = tobool(Properties.ok), escalon = tostring(Properties.escalon)
      | where ok == false
      | summarize fallos = count() by dependencia, escalon
    KQL

    time_aggregation_method = "Count"
    threshold               = 1
    operator                = "GreaterThanOrEqual"

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 2
      number_of_evaluation_periods             = 2
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.guardia.id]
  }
}
