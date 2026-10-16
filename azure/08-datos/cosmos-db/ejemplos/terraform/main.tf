# Azure Cosmos DB (API para NoSQL) listo para microservicios (versión de estudio):
#   - Cuenta SIN claves (solo Entra ID + RBAC de datos), TLS 1.2, consistencia Session
#   - dev: serverless, una región, firewall por IP  |  prod: 2 regiones con zonas, autoscale, Private Endpoint, público cerrado
#   - Contenedores: pedidos (índice afinado, clave única, índice compuesto), carritos (TTL 7 días), leases (change feed)
#   - Roles de datos: Data Contributor para la API de pedidos, Data Reader para reportes, rol personalizado sin borrado
#   - Diagnóstico a Log Analytics (tablas específicas) y alertas de RU normalizadas y de 429
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

variable "region_secundaria" {
  description = "Segunda región (solo prod)"
  type        = string
  default     = "centralus"
}

variable "entorno" {
  description = "dev: serverless, una región y firewall por IP | prod: autoscale, dos regiones con zonas y red privada"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.entorno)
    error_message = "entorno debe ser dev o prod."
  }
}

variable "mi_ip" {
  description = "IP pública del desarrollador (solo dev)"
  type        = string
  default     = "203.0.113.10"
}

variable "app_pedidos_principal_id" {
  description = "Object id de la identidad administrada de la API de pedidos"
  type        = string
  default     = "00000000-0000-0000-0000-0000000000a1"
}

variable "reportes_principal_id" {
  description = "Object id de la identidad del servicio de reportes (solo lectura)"
  type        = string
  default     = "00000000-0000-0000-0000-0000000000b2"
}

variable "correo_alertas" {
  type    = string
  default = "operaciones@modalima.example"
}

locals {
  prod = var.entorno == "prod"

  # Roles integrados de datos de Cosmos DB (no son roles de Azure RBAC)
  rol_lector       = "00000000-0000-0000-0000-000000000001"
  rol_contribuidor = "00000000-0000-0000-0000-000000000002"
}

resource "random_string" "sufijo" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-estudio-cosmos"
  location = var.ubicacion
}

# ---------------------------------------------------------------- Cuenta
resource "azurerm_cosmosdb_account" "cosmos" {
  name                = "cosmos-modalima-${random_string.sufijo.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  # Sin claves: solo identidades de Entra + roles de datos
  local_authentication_disabled = true
  minimal_tls_version           = "Tls12"

  # Red: prod cerrado (solo Private Endpoint); dev abierto pero filtrado por IP
  public_network_access_enabled = !local.prod
  ip_range_filter               = local.prod ? [] : [var.mi_ip]

  automatic_failover_enabled       = local.prod
  multiple_write_locations_enabled = false

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = azurerm_resource_group.rg.location
    failover_priority = 0
    zone_redundant    = local.prod
  }

  dynamic "geo_location" {
    for_each = local.prod ? [var.region_secundaria] : []
    content {
      location          = geo_location.value
      failover_priority = 1
      zone_redundant    = true
    }
  }

  # dev: serverless (sin RU aprovisionadas)
  dynamic "capabilities" {
    for_each = local.prod ? [] : ["EnableServerless"]
    content {
      name = capabilities.value
    }
  }

  # prod: copia continua con restauración a un instante; dev: periódica
  dynamic "backup" {
    for_each = local.prod ? [1] : []
    content {
      type = "Continuous"
      tier = "Continuous30Days"
    }
  }

  dynamic "backup" {
    for_each = local.prod ? [] : [1]
    content {
      type                = "Periodic"
      interval_in_minutes = 240
      retention_in_hours  = 8
      storage_redundancy  = "Local"
    }
  }

  identity {
    type = "SystemAssigned"
  }
}

# ---------------------------------------------------------------- Base y contenedores
resource "azurerm_cosmosdb_sql_database" "pedidos" {
  name                = "pedidos-db"
  resource_group_name = azurerm_resource_group.rg.name
  account_name        = azurerm_cosmosdb_account.cosmos.name
}

# Pedidos: un documento por pedido; clave de partición = cliente (lecturas "mis pedidos" a una sola partición)
resource "azurerm_cosmosdb_sql_container" "pedidos" {
  name                  = "pedidos"
  resource_group_name   = azurerm_resource_group.rg.name
  account_name          = azurerm_cosmosdb_account.cosmos.name
  database_name         = azurerm_cosmosdb_sql_database.pedidos.name
  partition_key_paths   = ["/clienteId"]
  partition_key_version = 2

  # -1 = TTL activado sin vencimiento por defecto: solo expiran los documentos con su propia propiedad "ttl"
  # (los eventos del Outbox). Sin esto, la propiedad ttl de cada documento se ignora.
  default_ttl = -1

  # Unicidad dentro de cada partición lógica (cada cliente)
  unique_key {
    paths = ["/referenciaExterna"]
  }

  dynamic "autoscale_settings" {
    for_each = local.prod ? [1] : []
    content {
      max_throughput = 10000 # escala entre 1 000 y 10 000 RU/s
    }
  }

  indexing_policy {
    indexing_mode = "consistent"

    included_path {
      path = "/*"
    }

    # Lo que nunca se filtra no se indexa: escrituras más baratas
    excluded_path {
      path = "/notas/*"
    }

    excluded_path {
      path = "/direccionEntrega/*"
    }

    excluded_path {
      path = "/\"_etag\"/?"
    }

    # Para: WHERE c.clienteId = @id AND c.estado = @e ORDER BY c.creadoEn DESC
    composite_index {
      index {
        path  = "/estado"
        order = "Ascending"
      }
      index {
        path  = "/creadoEn"
        order = "Descending"
      }
    }
  }
}

# Carritos: temporales; TTL por defecto de 7 días (604 800 s)
resource "azurerm_cosmosdb_sql_container" "carritos" {
  name                  = "carritos"
  resource_group_name   = azurerm_resource_group.rg.name
  account_name          = azurerm_cosmosdb_account.cosmos.name
  database_name         = azurerm_cosmosdb_sql_database.pedidos.name
  partition_key_paths   = ["/clienteId"]
  partition_key_version = 2
  default_ttl           = 604800

  dynamic "autoscale_settings" {
    for_each = local.prod ? [1] : []
    content {
      max_throughput = 4000
    }
  }
}

# Arrendamientos del procesador del change feed (estado y reparto entre instancias)
resource "azurerm_cosmosdb_sql_container" "leases" {
  name                  = "leases"
  resource_group_name   = azurerm_resource_group.rg.name
  account_name          = azurerm_cosmosdb_account.cosmos.name
  database_name         = azurerm_cosmosdb_sql_database.pedidos.name
  partition_key_paths   = ["/id"]
  partition_key_version = 2

  dynamic "autoscale_settings" {
    for_each = local.prod ? [1] : []
    content {
      max_throughput = 1000
    }
  }

  indexing_policy {
    indexing_mode = "consistent"

    excluded_path {
      path = "/*"
    }
  }
}

# ---------------------------------------------------------------- RBAC de datos
# La API de pedidos: leer y escribir en la base (alcance: la base de datos, no la cuenta)
resource "azurerm_cosmosdb_sql_role_assignment" "api_pedidos" {
  name                = uuidv5("url", "api-pedidos-contribuidor")
  resource_group_name = azurerm_resource_group.rg.name
  account_name        = azurerm_cosmosdb_account.cosmos.name
  role_definition_id  = "${azurerm_cosmosdb_account.cosmos.id}/sqlRoleDefinitions/${local.rol_contribuidor}"
  principal_id        = var.app_pedidos_principal_id
  scope               = "${azurerm_cosmosdb_account.cosmos.id}/dbs/${azurerm_cosmosdb_sql_database.pedidos.name}"
}

# Reportes: solo lectura
resource "azurerm_cosmosdb_sql_role_assignment" "reportes" {
  name                = uuidv5("url", "reportes-lector")
  resource_group_name = azurerm_resource_group.rg.name
  account_name        = azurerm_cosmosdb_account.cosmos.name
  role_definition_id  = "${azurerm_cosmosdb_account.cosmos.id}/sqlRoleDefinitions/${local.rol_lector}"
  principal_id        = var.reportes_principal_id
  scope               = "${azurerm_cosmosdb_account.cosmos.id}/dbs/${azurerm_cosmosdb_sql_database.pedidos.name}"
}

# Rol personalizado: crear, leer, reemplazar, consultar y leer el change feed, SIN permiso de borrado
resource "azurerm_cosmosdb_sql_role_definition" "sin_borrado" {
  name                = "Pedidos-SinBorrado"
  resource_group_name = azurerm_resource_group.rg.name
  account_name        = azurerm_cosmosdb_account.cosmos.name
  type                = "CustomRole"
  assignable_scopes   = [azurerm_cosmosdb_account.cosmos.id]

  permissions {
    data_actions = [
      "Microsoft.DocumentDB/databaseAccounts/readMetadata",
      "Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/items/create",
      "Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/items/read",
      "Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/items/replace",
      "Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/items/upsert",
      "Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/executeQuery",
      "Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/readChangeFeed",
    ]
  }
}

# ---------------------------------------------------------------- Red privada (solo prod)
resource "azurerm_virtual_network" "vnet" {
  count               = local.prod ? 1 : 0
  name                = "vnet-cosmos"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  address_space       = ["10.65.0.0/16"]
}

resource "azurerm_subnet" "pe" {
  count                = local.prod ? 1 : 0
  name                 = "snet-private-endpoints"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet[0].name
  address_prefixes     = ["10.65.1.0/24"]
}

resource "azurerm_private_dns_zone" "cosmos" {
  count               = local.prod ? 1 : 0
  name                = "privatelink.documents.azure.com"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "cosmos" {
  count                 = local.prod ? 1 : 0
  name                  = "enlace-cosmos"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.cosmos[0].name
  virtual_network_id    = azurerm_virtual_network.vnet[0].id
}

# Subrecurso "Sql" para la API para NoSQL. En modo directo, el SDK usa además los puertos 10250-10255
resource "azurerm_private_endpoint" "cosmos" {
  count               = local.prod ? 1 : 0
  name                = "pe-cosmos-sql"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  subnet_id           = azurerm_subnet.pe[0].id

  private_service_connection {
    name                           = "psc-cosmos"
    private_connection_resource_id = azurerm_cosmosdb_account.cosmos.id
    subresource_names              = ["Sql"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "zona-cosmos"
    private_dns_zone_ids = [azurerm_private_dns_zone.cosmos[0].id]
  }
}

# ---------------------------------------------------------------- Observabilidad
resource "azurerm_log_analytics_workspace" "log" {
  name                = "log-cosmos-${random_string.sufijo.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# "Dedicated" crea tablas específicas (CDBDataPlaneRequests, CDBPartitionKeyRUConsumption, ...)
resource "azurerm_monitor_diagnostic_setting" "cosmos" {
  name                           = "diag-cosmos"
  target_resource_id             = azurerm_cosmosdb_account.cosmos.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.log.id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category = "DataPlaneRequests"
  }

  enabled_log {
    category = "QueryRuntimeStatistics"
  }

  enabled_log {
    category = "PartitionKeyStatistics"
  }

  enabled_log {
    category = "PartitionKeyRUConsumption"
  }

  enabled_log {
    category = "ControlPlaneRequests"
  }

  enabled_metric {
    category = "Requests"
  }
}

resource "azurerm_monitor_action_group" "operaciones" {
  name                = "ag-operaciones-cosmos"
  resource_group_name = azurerm_resource_group.rg.name
  short_name          = "opscos"

  email_receiver {
    name          = "equipo"
    email_address = var.correo_alertas
  }
}

# Partición caliente o RU insuficientes: consumo normalizado cercano al 100 % de alguna partición
resource "azurerm_monitor_metric_alert" "ru_normalizadas" {
  count               = local.prod ? 1 : 0
  name                = "alerta-cosmos-ru-normalizadas"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_cosmosdb_account.cosmos.id]
  description         = "Consumo normalizado de RU alto: revisar partición caliente o subir el máximo de autoscale"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.DocumentDB/databaseAccounts"
    metric_name      = "NormalizedRUConsumption"
    aggregation      = "Maximum"
    operator         = "GreaterThan"
    threshold        = 90
  }

  action {
    action_group_id = azurerm_monitor_action_group.operaciones.id
  }
}

# Solicitudes limitadas (429)
resource "azurerm_monitor_metric_alert" "limitadas" {
  name                = "alerta-cosmos-429"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_cosmosdb_account.cosmos.id]
  description         = "Hay solicitudes con 429: el SDK reintenta, pero la latencia sube"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.DocumentDB/databaseAccounts"
    metric_name      = "TotalRequests"
    aggregation      = "Count"
    operator         = "GreaterThan"
    threshold        = 50

    dimension {
      name     = "StatusCode"
      operator = "Include"
      values   = ["429"]
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.operaciones.id
  }
}

output "endpoint" {
  value = azurerm_cosmosdb_account.cosmos.endpoint
}

output "cuenta" {
  value = azurerm_cosmosdb_account.cosmos.name
}

output "base_de_datos" {
  value = azurerm_cosmosdb_sql_database.pedidos.name
}

output "workspace_logs" {
  value = azurerm_log_analytics_workspace.log.id
}
