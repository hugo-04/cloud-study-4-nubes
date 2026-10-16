# Azure SQL Database listo para producción (versión de estudio):
#   - Servidor lógico con SOLO Entra ID (sin usuario/clave SQL), TLS 1.2, administrador = un grupo
#   - Base "pedidos": General Purpose; serverless en desarrollo (se pausa), provisionada en producción
#   - Copias: PITR 14 días + retención a largo plazo; almacenamiento de copias redundante en zona
#   - Red privada opcional (Private Endpoint "sqlServer" + zona privatelink.database.windows.net)
#   - Auditoría y diagnóstico a Log Analytics, Defender (alertas de amenazas) y alertas de CPU/deadlocks/conexiones
#   - Recuperación ante desastres opcional: segundo servidor en otra región + grupo de conmutación por error
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

variable "ubicacion_dr" {
  type    = string
  default = "centralus"
}

variable "entorno" {
  description = "dev usa serverless con pausa; prod usa cómputo provisionado con redundancia de zona"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.entorno)
    error_message = "entorno debe ser dev o prod."
  }
}

variable "grupo_admin_object_id" {
  description = "Object id del grupo de Entra (DBAdmins) que administra el servidor"
  type        = string
  default     = "00000000-0000-0000-0000-0000000000aa"
}

variable "red_privada" {
  description = "true: sin acceso público; se accede por Private Endpoint"
  type        = bool
  default     = false
}

variable "crear_dr" {
  description = "true: crea un segundo servidor y un grupo de conmutación por error"
  type        = bool
  default     = false
}

variable "correo_alertas" {
  type    = string
  default = "operaciones@modalima.example"
}

locals {
  prod = var.entorno == "prod"
}

resource "random_string" "sufijo" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-estudio-azuresql"
  location = var.ubicacion
}

# ---------------------------------------------------------------- Servidor lógico
resource "azurerm_mssql_server" "sql" {
  name                          = "sql-modalima-${random_string.sufijo.result}"
  resource_group_name           = azurerm_resource_group.rg.name
  location                      = azurerm_resource_group.rg.location
  version                       = "12.0"
  minimum_tls_version           = "1.2"
  public_network_access_enabled = !var.red_privada

  # Solo Entra ID: no existe usuario "sa" ni contraseñas SQL
  azuread_administrator {
    login_username              = "DBAdmins"
    object_id                   = var.grupo_admin_object_id
    azuread_authentication_only = true
  }

  identity {
    type = "SystemAssigned"
  }
}

# ---------------------------------------------------------------- Base de datos
resource "azurerm_mssql_database" "pedidos" {
  name      = "pedidos"
  server_id = azurerm_mssql_server.sql.id
  collation = "SQL_Latin1_General_CP1_CI_AS"

  # dev: serverless 0,5-2 vCore con pausa a los 60 min | prod: 4 vCore provisionado
  sku_name                    = local.prod ? "GP_Gen5_4" : "GP_S_Gen5_2"
  min_capacity                = local.prod ? null : 0.5
  auto_pause_delay_in_minutes = local.prod ? null : 60
  max_size_gb                 = 64
  zone_redundant              = local.prod # redundancia de zona solo en producción
  storage_account_type        = local.prod ? "Zone" : "Local"

  short_term_retention_policy {
    retention_days           = 14 # PITR: volver a cualquier instante de los últimos 14 días
    backup_interval_in_hours = 12
  }

  long_term_retention_policy {
    weekly_retention  = "P4W"
    monthly_retention = "P12M"
    yearly_retention  = "P5Y"
    week_of_year      = 1
  }

  # En producción conviene proteger contra borrado accidental:
  # lifecycle { prevent_destroy = true }
}

# Pool elástico opcional (SaaS con una base por cliente): descomenta y asigna las bases al pool
# resource "azurerm_mssql_elasticpool" "clientes" {
#   name                = "pool-clientes"
#   resource_group_name = azurerm_resource_group.rg.name
#   location            = azurerm_resource_group.rg.location
#   server_name         = azurerm_mssql_server.sql.name
#   max_size_gb         = 256
#   sku {
#     name     = "GP_Gen5"
#     tier     = "GeneralPurpose"
#     family   = "Gen5"
#     capacity = 4
#   }
#   per_database_settings {
#     min_capacity = 0.25
#     max_capacity = 2
#   }
# }

# ---------------------------------------------------------------- Red privada
resource "azurerm_virtual_network" "vnet" {
  count               = var.red_privada ? 1 : 0
  name                = "vnet-azuresql"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  address_space       = ["10.63.0.0/16"]
}

resource "azurerm_subnet" "privado" {
  count                = var.red_privada ? 1 : 0
  name                 = "snet-private-endpoints"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet[0].name
  address_prefixes     = ["10.63.2.0/24"]
}

resource "azurerm_private_dns_zone" "sql" {
  count               = var.red_privada ? 1 : 0
  name                = "privatelink.database.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "sql" {
  count                 = var.red_privada ? 1 : 0
  name                  = "enlace-azuresql"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.sql[0].name
  virtual_network_id    = azurerm_virtual_network.vnet[0].id
}

resource "azurerm_private_endpoint" "sql" {
  count               = var.red_privada ? 1 : 0
  name                = "pe-azuresql"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  subnet_id           = azurerm_subnet.privado[0].id

  private_service_connection {
    name                           = "psc-azuresql"
    private_connection_resource_id = azurerm_mssql_server.sql.id
    subresource_names              = ["sqlServer"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-azuresql"
    private_dns_zone_ids = [azurerm_private_dns_zone.sql[0].id]
  }
}

# ---------------------------------------------------------------- Observabilidad y seguridad
resource "azurerm_log_analytics_workspace" "log" {
  name                = "log-azuresql-${random_string.sufijo.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# Auditoría del servidor hacia Log Analytics (se activa con la bandera + el diagnóstico de master)
resource "azurerm_mssql_server_extended_auditing_policy" "auditoria" {
  server_id              = azurerm_mssql_server.sql.id
  log_monitoring_enabled = true
}

resource "azurerm_monitor_diagnostic_setting" "auditoria_master" {
  name                       = "diag-auditoria"
  target_resource_id         = "${azurerm_mssql_server.sql.id}/databases/master"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log.id

  enabled_log {
    category = "SQLSecurityAuditEvents"
  }
}

# Registros de rendimiento y errores de la base de datos
resource "azurerm_monitor_diagnostic_setting" "pedidos" {
  name                       = "diag-pedidos"
  target_resource_id         = azurerm_mssql_database.pedidos.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log.id

  enabled_log {
    category = "SQLInsights"
  }
  enabled_log {
    category = "Errors"
  }
  enabled_log {
    category = "Timeouts"
  }
  enabled_log {
    category = "Blocks"
  }
  enabled_log {
    category = "Deadlocks"
  }
  enabled_log {
    category = "QueryStoreRuntimeStatistics"
  }
  enabled_log {
    category = "QueryStoreWaitStatistics"
  }
  enabled_log {
    category = "AutomaticTuning"
  }

  enabled_metric {
    category = "Basic"
  }
}

# Microsoft Defender for SQL: detección de inyección SQL, accesos anómalos, etc.
resource "azurerm_mssql_server_security_alert_policy" "defender" {
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_mssql_server.sql.name
  state               = "Enabled"
  retention_days      = 30
}

resource "azurerm_monitor_action_group" "operaciones" {
  name                = "ag-operaciones-sql"
  resource_group_name = azurerm_resource_group.rg.name
  short_name          = "opssql"

  email_receiver {
    name          = "equipo"
    email_address = var.correo_alertas
  }
}

locals {
  alertas = {
    cpu = {
      metrica = "cpu_percent"
      umbral  = 80
      agrega  = "Average"
      desc    = "CPU sostenida alta"
    }
    deadlocks = {
      metrica = "deadlock"
      umbral  = 0
      agrega  = "Total"
      desc    = "Interbloqueos detectados"
    }
    conexiones_fallidas = {
      metrica = "connection_failed"
      umbral  = 5
      agrega  = "Total"
      desc    = "Conexiones fallidas"
    }
    almacenamiento = {
      metrica = "storage_percent"
      umbral  = 85
      agrega  = "Maximum"
      desc    = "Almacenamiento casi lleno"
    }
    workers = {
      metrica = "workers_percent"
      umbral  = 80
      agrega  = "Maximum"
      desc    = "Hilos de trabajo cerca del límite (demasiadas conexiones/consultas concurrentes)"
    }
  }
}

resource "azurerm_monitor_metric_alert" "sql" {
  for_each = local.alertas

  name                = "alerta-sql-${each.key}"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_mssql_database.pedidos.id]
  description         = each.value.desc
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.Sql/servers/databases"
    metric_name      = each.value.metrica
    aggregation      = each.value.agrega
    operator         = "GreaterThan"
    threshold        = each.value.umbral
  }

  action {
    action_group_id = azurerm_monitor_action_group.operaciones.id
  }
}

# ---------------------------------------------------------------- Recuperación ante desastres (opcional)
resource "azurerm_mssql_server" "secundario" {
  count                         = var.crear_dr ? 1 : 0
  name                          = "sql-modalima-dr-${random_string.sufijo.result}"
  resource_group_name           = azurerm_resource_group.rg.name
  location                      = var.ubicacion_dr
  version                       = "12.0"
  minimum_tls_version           = "1.2"
  public_network_access_enabled = !var.red_privada

  azuread_administrator {
    login_username              = "DBAdmins"
    object_id                   = var.grupo_admin_object_id
    azuread_authentication_only = true
  }
}

# Punto de conexión estable: fg-modalima.database.windows.net (siempre apunta a la primaria)
resource "azurerm_mssql_failover_group" "fg" {
  count     = var.crear_dr ? 1 : 0
  name      = "fg-modalima-${random_string.sufijo.result}"
  server_id = azurerm_mssql_server.sql.id
  databases = [azurerm_mssql_database.pedidos.id]

  partner_server {
    id = azurerm_mssql_server.secundario[0].id
  }

  read_write_endpoint_failover_policy {
    mode          = "Automatic"
    grace_minutes = 60 # espera antes de conmutar automáticamente (puede haber pérdida de datos)
  }
}

output "servidor" {
  value = azurerm_mssql_server.sql.fully_qualified_domain_name
}

output "cadena_jdbc" {
  value = "jdbc:sqlserver://${azurerm_mssql_server.sql.fully_qualified_domain_name}:1433;database=${azurerm_mssql_database.pedidos.name};encrypt=true;trustServerCertificate=false;hostNameInCertificate=*.database.windows.net;loginTimeout=30;authentication=ActiveDirectoryManagedIdentity"
}

output "workspace_logs" {
  value = azurerm_log_analytics_workspace.log.id
}
