# PostgreSQL Flexible Server listo para producción (versión de estudio):
#   - Servidor con SOLO Entra ID (sin contraseña de administrador), TLS, HA entre zonas en prod
#   - Red privada: subred delegada + zona DNS privada (integración con VNet) o público cerrado + firewall (dev)
#   - Parámetros: extensiones permitidas, PgBouncer, Query Store, registro de consultas lentas, tiempos máximos
#   - Copias PITR 14 días, ventana de mantenimiento, réplica de lectura opcional
#   - Diagnóstico a Log Analytics y alertas de CPU, memoria, almacenamiento, conexiones y retraso de réplica
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

variable "entorno" {
  description = "dev: Burstable sin HA y red pública cerrada con firewall | prod: General Purpose, HA entre zonas y red privada"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.entorno)
    error_message = "entorno debe ser dev o prod."
  }
}

variable "tenant_id" {
  description = "Tenant de Entra ID"
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "grupo_admin_object_id" {
  description = "Object id del grupo de Entra (DBAdmins) administrador del servidor"
  type        = string
  default     = "00000000-0000-0000-0000-0000000000aa"
}

variable "crear_replica" {
  description = "true: crea una réplica de lectura"
  type        = bool
  default     = false
}

variable "mi_ip" {
  description = "IP pública del desarrollador (solo entorno dev)"
  type        = string
  default     = "203.0.113.10"
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
  name     = "rg-estudio-postgres"
  location = var.ubicacion
}

# ---------------------------------------------------------------- Red privada (solo producción)
resource "azurerm_virtual_network" "vnet" {
  count               = local.prod ? 1 : 0
  name                = "vnet-postgres"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  address_space       = ["10.64.0.0/16"]
}

# La subred se DELEGA al servicio: solo puede contener servidores PostgreSQL Flexible
resource "azurerm_subnet" "postgres" {
  count                = local.prod ? 1 : 0
  name                 = "snet-postgres"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet[0].name
  address_prefixes     = ["10.64.1.0/24"]

  delegation {
    name = "postgres"

    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# El nombre de la zona debe terminar en .postgres.database.azure.com
resource "azurerm_private_dns_zone" "postgres" {
  count               = local.prod ? 1 : 0
  name                = "modalima.private.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  count                 = local.prod ? 1 : 0
  name                  = "enlace-postgres"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.postgres[0].name
  virtual_network_id    = azurerm_virtual_network.vnet[0].id
}

# ---------------------------------------------------------------- Servidor
resource "azurerm_postgresql_flexible_server" "pg" {
  name                = "pg-modalima-${random_string.sufijo.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  version             = "17"
  zone                = "1"

  sku_name   = local.prod ? "GP_Standard_D4ds_v5" : "B_Standard_B1ms"
  storage_mb = local.prod ? 262144 : 32768 # 256 GiB / 32 GiB (el almacenamiento solo crece)
  # storage_tier = "P15"                   # opcional: IOPS asociadas al nivel de Premium SSD

  auto_grow_enabled = true

  backup_retention_days        = 14 # PITR
  geo_redundant_backup_enabled = local.prod

  # Red: privada en prod; pública cerrada con firewall en dev
  delegated_subnet_id           = local.prod ? azurerm_subnet.postgres[0].id : null
  private_dns_zone_id           = local.prod ? azurerm_private_dns_zone.postgres[0].id : null
  public_network_access_enabled = !local.prod

  # Solo Entra ID: sin usuario/contraseña de administrador
  authentication {
    active_directory_auth_enabled = true
    password_auth_enabled         = false
    tenant_id                     = var.tenant_id
  }

  dynamic "high_availability" {
    for_each = local.prod ? [1] : []
    content {
      mode                      = "ZoneRedundant"
      standby_availability_zone = "2"
    }
  }

  maintenance_window {
    day_of_week  = 0 # domingo
    start_hour   = 3
    start_minute = 0
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]

  lifecycle {
    ignore_changes = [zone, high_availability[0].standby_availability_zone]
  }
}

# Administrador de Entra: un grupo, no una persona
resource "azurerm_postgresql_flexible_server_active_directory_administrator" "admin" {
  server_name         = azurerm_postgresql_flexible_server.pg.name
  resource_group_name = azurerm_resource_group.rg.name
  tenant_id           = var.tenant_id
  object_id           = var.grupo_admin_object_id
  principal_name      = "DBAdmins"
  principal_type      = "Group"
}

resource "azurerm_postgresql_flexible_server_database" "pedidos" {
  name      = "pedidos"
  server_id = azurerm_postgresql_flexible_server.pg.id
  collation = "en_US.utf8"
  charset   = "UTF8"
}

# Firewall solo en dev (en prod no hay acceso público)
resource "azurerm_postgresql_flexible_server_firewall_rule" "dev" {
  count            = local.prod ? 0 : 1
  name             = "mi-ip"
  server_id        = azurerm_postgresql_flexible_server.pg.id
  start_ip_address = var.mi_ip
  end_ip_address   = var.mi_ip
}

# ---------------------------------------------------------------- Parámetros del servidor
locals {
  parametros = {
    "azure.extensions"                      = "PG_STAT_STATEMENTS,PGCRYPTO,UUID-OSSP,PG_TRGM,PGAUDIT,PG_CRON,VECTOR,BTREE_GIN"
    "shared_preload_libraries"              = "pg_stat_statements,pgaudit,pg_cron"
    "pgbouncer.enabled"                     = "true"
    "pgbouncer.pool_mode"                   = "TRANSACTION"
    "pgbouncer.default_pool_size"           = "50"
    "pg_qs.query_capture_mode"              = "top" # Query Store
    "pgms_wait_sampling.query_capture_mode" = "all"
    "log_min_duration_statement"            = "500" # registra consultas de más de 500 ms
    "idle_in_transaction_session_timeout"   = "60000"
    "statement_timeout"                     = "60000"
    "pgaudit.log"                           = "ddl,role"
    "track_io_timing"                       = "on"
  }
}

resource "azurerm_postgresql_flexible_server_configuration" "p" {
  for_each = local.parametros

  name      = each.key
  server_id = azurerm_postgresql_flexible_server.pg.id
  value     = each.value
}

# ---------------------------------------------------------------- Réplica de lectura (opcional)
resource "azurerm_postgresql_flexible_server" "replica" {
  count               = var.crear_replica ? 1 : 0
  name                = "pg-modalima-lectura-${random_string.sufijo.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  create_mode         = "Replica"
  source_server_id    = azurerm_postgresql_flexible_server.pg.id

  delegated_subnet_id = local.prod ? azurerm_subnet.postgres[0].id : null
  private_dns_zone_id = local.prod ? azurerm_private_dns_zone.postgres[0].id : null

  lifecycle {
    ignore_changes = [zone]
  }
}

# ---------------------------------------------------------------- Observabilidad
resource "azurerm_log_analytics_workspace" "log" {
  name                = "log-postgres-${random_string.sufijo.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_monitor_diagnostic_setting" "pg" {
  name                       = "diag-postgres"
  target_resource_id         = azurerm_postgresql_flexible_server.pg.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log.id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_action_group" "operaciones" {
  name                = "ag-operaciones-pg"
  resource_group_name = azurerm_resource_group.rg.name
  short_name          = "opspg"

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
    memoria = {
      metrica = "memory_percent"
      umbral  = 85
      agrega  = "Average"
      desc    = "Memoria alta"
    }
    almacenamiento = {
      metrica = "storage_percent"
      umbral  = 85
      agrega  = "Maximum"
      desc    = "Almacenamiento casi lleno (no se puede reducir después)"
    }
    conexiones = {
      metrica = "active_connections"
      umbral  = 200
      agrega  = "Maximum"
      desc    = "Muchas conexiones activas (revisar pools y PgBouncer)"
    }
    conexiones_fallidas = {
      metrica = "connections_failed"
      umbral  = 10
      agrega  = "Total"
      desc    = "Conexiones fallidas"
    }
  }
}

resource "azurerm_monitor_metric_alert" "pg" {
  for_each = local.alertas

  name                = "alerta-pg-${each.key}"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_postgresql_flexible_server.pg.id]
  description         = each.value.desc
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = each.value.metrica
    aggregation      = each.value.agrega
    operator         = "GreaterThan"
    threshold        = each.value.umbral
  }

  action {
    action_group_id = azurerm_monitor_action_group.operaciones.id
  }
}

output "servidor" {
  value = azurerm_postgresql_flexible_server.pg.fqdn
}

output "cadena_jdbc" {
  value = "jdbc:postgresql://${azurerm_postgresql_flexible_server.pg.fqdn}:5432/pedidos?sslmode=verify-full"
}

output "cadena_jdbc_pgbouncer" {
  value = "jdbc:postgresql://${azurerm_postgresql_flexible_server.pg.fqdn}:6432/pedidos?sslmode=verify-full&prepareThreshold=0"
}

output "workspace_logs" {
  value = azurerm_log_analytics_workspace.log.id
}
