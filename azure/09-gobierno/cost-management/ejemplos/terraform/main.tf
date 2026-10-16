# Cost Management como código (versión de estudio) para ModaLima.
#   - Grupo de acciones "finops" (correo + webhook hacia una Function que apaga lo etiquetado auto-apagar=si)
#   - Presupuesto mensual de la suscripción: avisos al 50 % y 80 % real, acción al 100 % real, aviso temprano al 110 % pronosticado
#   - Presupuesto del grupo de recursos de Sandbox, filtrado por etiqueta env=sandbox, con acción al 100 %
#   - Presupuesto de un grupo de administración (solo correo: los grupos de acciones no aplican a ese alcance)
#   - Alerta de anomalías de la suscripción
#   - Exportación diaria (costo real, mes hasta la fecha) a una cuenta de almacenamiento central
# Los presupuestos NO detienen el gasto: avisan y, con un grupo de acciones, disparan TU automatización.
# terraform init && terraform plan

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
  features {}
}

variable "ubicacion" {
  type    = string
  default = "eastus2"
}

variable "inicio_presupuesto" {
  description = "Primer día de un mes, en UTC (los presupuestos exigen empezar el día 1)"
  type        = string
  default     = "2026-11-01T00:00:00Z"
}

variable "monto_suscripcion" {
  description = "Presupuesto mensual de la suscripción, en la moneda de facturación"
  type        = number
  default     = 5000
}

variable "monto_sandbox" {
  type    = number
  default = 800
}

variable "monto_grupo_admin" {
  type    = number
  default = 20000
}

variable "grupo_de_administracion" {
  description = "ID del grupo de administración (ruta completa) para el presupuesto de la empresa; vacío = no crear"
  type        = string
  default     = ""
}

variable "correos_finops" {
  type    = list(string)
  default = ["finops@modalima.example"]
}

variable "url_webhook_apagado" {
  description = "URL de la Function que apaga recursos etiquetados (HTTPS)"
  type        = string
  default     = "https://func-finops-modalima.azurewebsites.net/api/apagar"
}

data "azurerm_subscription" "actual" {}

resource "azurerm_resource_group" "finops" {
  name     = "rg-modalima-finops"
  location = var.ubicacion
  tags = {
    env         = "prod"
    owner       = "finops"
    cost-center = "cc-1000"
  }
}

resource "azurerm_resource_group" "sandbox" {
  name     = "rg-modalima-sandbox"
  location = var.ubicacion
  tags = {
    env         = "sandbox"
    owner       = "plataforma"
    cost-center = "cc-9000"
  }
}

# --- Grupo de acciones: qué pasa cuando un presupuesto alcanza un umbral -------------------------------
resource "azurerm_monitor_action_group" "finops" {
  name                = "ag-finops"
  resource_group_name = azurerm_resource_group.finops.name
  short_name          = "finops"

  dynamic "email_receiver" {
    for_each = var.correos_finops
    content {
      name                    = "correo-${email_receiver.key}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }

  webhook_receiver {
    name                    = "apagar-sandbox"
    service_uri             = var.url_webhook_apagado
    use_common_alert_schema = true
  }
}

# --- Presupuesto de la suscripción ----------------------------------------------------------------------
resource "azurerm_consumption_budget_subscription" "mensual" {
  name            = "presupuesto-mensual-${data.azurerm_subscription.actual.display_name}"
  subscription_id = data.azurerm_subscription.actual.id
  amount          = var.monto_suscripcion
  time_grain      = "Monthly"

  time_period {
    start_date = var.inicio_presupuesto
  }

  # Avisos humanos
  notification {
    enabled        = true
    threshold      = 50
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = var.correos_finops
  }

  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = var.correos_finops
    contact_roles  = ["Owner"]
  }

  # Aviso temprano: el pronóstico indica que nos pasaremos
  notification {
    enabled        = true
    threshold      = 110
    operator       = "GreaterThan"
    threshold_type = "Forecasted"
    contact_emails = var.correos_finops
    contact_roles  = ["Owner"]
  }

  # Acción: al llegar al 100 % real, el grupo de acciones avisa y dispara la automatización
  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = var.correos_finops
    contact_groups = [azurerm_monitor_action_group.finops.id]
  }
}

# --- Presupuesto de Sandbox: solo lo etiquetado env=sandbox del grupo de recursos --------------------------
resource "azurerm_consumption_budget_resource_group" "sandbox" {
  name              = "presupuesto-sandbox"
  resource_group_id = azurerm_resource_group.sandbox.id
  amount            = var.monto_sandbox
  time_grain        = "Monthly"

  time_period {
    start_date = var.inicio_presupuesto
  }

  filter {
    tag {
      name     = "env"
      operator = "In"
      values   = ["sandbox"]
    }
  }

  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = var.correos_finops
  }

  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = var.correos_finops
    contact_groups = [azurerm_monitor_action_group.finops.id]
  }
}

# --- Presupuesto de un grupo de administración (SOLO correo: no admite grupos de acciones) -----------------
resource "azurerm_consumption_budget_management_group" "empresa" {
  count               = var.grupo_de_administracion == "" ? 0 : 1
  name                = "presupuesto-empresa"
  management_group_id = var.grupo_de_administracion
  amount              = var.monto_grupo_admin
  time_grain          = "Monthly"

  time_period {
    start_date = var.inicio_presupuesto
  }

  notification {
    enabled        = true
    threshold      = 90
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = var.correos_finops
  }
}

# --- Anomalías de la suscripción (hasta cinco alertas por suscripción) -----------------------------------
resource "azurerm_cost_anomaly_alert" "suscripcion" {
  name            = "anomalias-${data.azurerm_subscription.actual.display_name}"
  display_name    = "Anomalías de costo de ModaLima"
  subscription_id = data.azurerm_subscription.actual.id
  email_subject   = "Anomalía de costo detectada"
  email_addresses = var.correos_finops
  message         = "Revisa el análisis de costos por grupo de recursos."
}

# --- Exportación diaria a un almacenamiento central ---------------------------------------------------------
resource "azurerm_storage_account" "costos" {
  name                            = "stmodalimacostos01"
  resource_group_name             = azurerm_resource_group.finops.name
  location                        = var.ubicacion
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  tags                            = azurerm_resource_group.finops.tags
}

resource "azurerm_storage_container" "costos" {
  name                  = "exportaciones-costos"
  storage_account_id    = azurerm_storage_account.costos.id
  container_access_type = "private"
}

resource "azurerm_subscription_cost_management_export" "diaria" {
  name                         = "export-modalima-diario"
  subscription_id              = data.azurerm_subscription.actual.id
  recurrence_type              = "Daily"
  recurrence_period_start_date = "2026-11-01T00:00:00Z"
  recurrence_period_end_date   = "2030-12-31T00:00:00Z"

  export_data_storage_location {
    container_id     = azurerm_storage_container.costos.id
    root_folder_path = "/modalima"
  }

  export_data_options {
    type       = "ActualCost"
    time_frame = "MonthToDate"
  }
}

output "presupuestos" {
  value = {
    suscripcion = azurerm_consumption_budget_subscription.mensual.id
    sandbox     = azurerm_consumption_budget_resource_group.sandbox.id
  }
}
