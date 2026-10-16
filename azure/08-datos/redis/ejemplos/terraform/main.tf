# Azure Managed Redis listo para microservicios (versión de estudio):
#   - Instancia con SKU configurable, alta disponibilidad, política de clúster y de expulsión elegidas
#   - Autenticación SOLO con Entra ID (claves de acceso desactivadas en prod) + asignación de la identidad de la aplicación
#   - dev: Balanced_B0 sin HA y acceso público (protegido por TLS + Entra) | prod: Balanced_B5 con HA, Private Endpoint y público cerrado
#   - Módulos opcionales (RedisJSON, RediSearch...), persistencia RDB opcional, geo-replicación activa opcional
#   - Diagnóstico a Log Analytics (ConnectionEvents) y alertas de memoria, carga del servidor y salud de geo-replicación
# terraform init && terraform plan   (terraform destroy al terminar)
# Nota: la política de clúster (OSS/Enterprise) y los módulos NO se pueden cambiar después de crear la base.

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
  description = "Segunda región (solo si crear_geo = true)"
  type        = string
  default     = "centralus"
}

variable "entorno" {
  description = "dev: Balanced_B0, sin HA, acceso público | prod: Balanced_B5, HA, Private Endpoint"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.entorno)
    error_message = "entorno debe ser dev o prod."
  }
}

variable "politica_cluster" {
  description = "OSSCluster: mejor rendimiento, exige cliente con soporte de clúster | EnterpriseCluster: un solo endpoint, cualquier cliente, requerida por RediSearch"
  type        = string
  default     = "OSSCluster"

  validation {
    condition     = contains(["OSSCluster", "EnterpriseCluster"], var.politica_cluster)
    error_message = "politica_cluster debe ser OSSCluster o EnterpriseCluster."
  }
}

variable "politica_expulsion" {
  description = "VolatileLRU (caché con TTL), AllKeysLRU (caché general) o NoEviction (datos que no se pueden perder; obligatoria con RediSearch)"
  type        = string
  default     = "VolatileLRU"
}

variable "modulos" {
  description = "Módulos a habilitar al crear (no se pueden cambiar después). RediSearch exige EnterpriseCluster + NoEviction"
  type        = list(string)
  default     = []
}

variable "persistencia" {
  description = "true: copia RDB cada hora (para sesiones o datos que conviene recuperar tras un reinicio). No compatible con geo-replicación"
  type        = bool
  default     = false
}

variable "crear_geo" {
  description = "true: crea una segunda instancia en otra región y las enlaza (geo-replicación activa; solo prod)"
  type        = bool
  default     = false
}

variable "app_pedidos_principal_id" {
  description = "Object id de la identidad administrada de la API de pedidos"
  type        = string
  default     = "00000000-0000-0000-0000-0000000000a1"
}

variable "correo_alertas" {
  type    = string
  default = "operaciones@modalima.example"
}

locals {
  prod       = var.entorno == "prod"
  grupo_geo  = (local.prod && var.crear_geo) ? "grp-modalima-cache" : null
  con_pe     = local.prod
  sku        = local.prod ? "Balanced_B5" : "Balanced_B0"
  frecuencia = var.persistencia ? "1h" : null
}

resource "random_string" "sufijo" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-estudio-redis"
  location = var.ubicacion
}

# ---------------------------------------------------------------- Instancia principal
resource "azurerm_managed_redis" "redis" {
  name                = "amr-modalima-${random_string.sufijo.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku_name            = local.sku

  # Sin HA no hay réplica ni SLA: solo para desarrollo
  high_availability_enabled = local.prod

  # No hay reglas de firewall por IP: o público (TLS + Entra) o solo Private Endpoint
  public_network_access = local.prod ? "Disabled" : "Enabled"

  default_database {
    client_protocol = "Encrypted" # TLS, puerto 10000

    clustering_policy = var.politica_cluster
    eviction_policy   = var.politica_expulsion

    # Sin claves de acceso en prod: solo identidades de Entra
    access_keys_authentication_enabled = !local.prod

    geo_replication_group_name                  = local.grupo_geo
    persistence_redis_database_backup_frequency = local.frecuencia

    dynamic "module" {
      for_each = var.modulos
      content {
        name = module.value
      }
    }
  }

  identity {
    type = "SystemAssigned"
  }
}

# Da acceso de datos a la identidad de la API (política de acceso "default": todos los comandos)
resource "azurerm_managed_redis_access_policy_assignment" "api_pedidos" {
  managed_redis_id = azurerm_managed_redis.redis.id
  object_id        = var.app_pedidos_principal_id
}

# ---------------------------------------------------------------- Segunda región (geo-replicación activa, opcional)
resource "azurerm_managed_redis" "secundaria" {
  count               = (local.prod && var.crear_geo) ? 1 : 0
  name                = "amr-modalima-2-${random_string.sufijo.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.region_secundaria
  sku_name            = local.sku # el grupo exige la misma SKU, política de clúster, de expulsión y módulos

  high_availability_enabled = true
  public_network_access     = "Disabled"

  default_database {
    client_protocol                    = "Encrypted"
    clustering_policy                  = var.politica_cluster
    eviction_policy                    = var.politica_expulsion
    access_keys_authentication_enabled = false
    geo_replication_group_name         = local.grupo_geo

    dynamic "module" {
      for_each = var.modulos
      content {
        name = module.value
      }
    }
  }
}

resource "azurerm_managed_redis_geo_replication" "grupo" {
  count            = (local.prod && var.crear_geo) ? 1 : 0
  managed_redis_id = azurerm_managed_redis.redis.id

  linked_managed_redis_ids = [azurerm_managed_redis.secundaria[0].id]
}

# ---------------------------------------------------------------- Red privada (solo prod)
resource "azurerm_virtual_network" "vnet" {
  count               = local.con_pe ? 1 : 0
  name                = "vnet-redis"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  address_space       = ["10.66.0.0/16"]
}

resource "azurerm_subnet" "pe" {
  count                = local.con_pe ? 1 : 0
  name                 = "snet-private-endpoints"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet[0].name
  address_prefixes     = ["10.66.1.0/24"]
}

resource "azurerm_private_dns_zone" "redis" {
  count               = local.con_pe ? 1 : 0
  name                = "privatelink.redis.azure.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "redis" {
  count                 = local.con_pe ? 1 : 0
  name                  = "enlace-redis"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.redis[0].name
  virtual_network_id    = azurerm_virtual_network.vnet[0].id
}

# Subrecurso "redisEnterprise". Los clientes usan <nombre>.<region>.redis.azure.net:10000
resource "azurerm_private_endpoint" "redis" {
  count               = local.con_pe ? 1 : 0
  name                = "pe-redis"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  subnet_id           = azurerm_subnet.pe[0].id

  private_service_connection {
    name                           = "psc-redis"
    private_connection_resource_id = azurerm_managed_redis.redis.id
    subresource_names              = ["redisEnterprise"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "zona-redis"
    private_dns_zone_ids = [azurerm_private_dns_zone.redis[0].id]
  }
}

# ---------------------------------------------------------------- Observabilidad
resource "azurerm_log_analytics_workspace" "log" {
  name                = "log-redis-${random_string.sufijo.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_monitor_diagnostic_setting" "redis" {
  name                       = "diag-redis"
  target_resource_id         = azurerm_managed_redis.redis.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log.id

  enabled_log {
    category = "ConnectionEvents" # tabla REDConnectionEvents
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_action_group" "operaciones" {
  name                = "ag-operaciones-redis"
  resource_group_name = azurerm_resource_group.rg.name
  short_name          = "opsredis"

  email_receiver {
    name          = "equipo"
    email_address = var.correo_alertas
  }
}

locals {
  alertas = {
    memoria = {
      metrica  = "usedmemorypercentage"
      operador = "GreaterThan"
      umbral   = 80
      desc     = "Memoria alta: con NoEviction las escrituras fallarán; con otras políticas se expulsan claves"
    }
    carga = {
      metrica  = "serverLoad"
      operador = "GreaterThan"
      umbral   = 80
      desc     = "Carga del servidor alta: comandos pesados, claves calientes o SKU pequeña"
    }
  }
}

resource "azurerm_monitor_metric_alert" "redis" {
  for_each = local.alertas

  name                = "alerta-redis-${each.key}"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_managed_redis.redis.id]
  description         = each.value.desc
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.Cache/redisEnterprise"
    metric_name      = each.value.metrica
    aggregation      = "Maximum"
    operator         = each.value.operador
    threshold        = each.value.umbral
  }

  action {
    action_group_id = azurerm_monitor_action_group.operaciones.id
  }
}

# Salud de la geo-replicación (solo si hay grupo)
resource "azurerm_monitor_metric_alert" "geo" {
  count               = (local.prod && var.crear_geo) ? 1 : 0
  name                = "alerta-redis-geo-no-sana"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_managed_redis.redis.id]
  description         = "La geo-replicación no está sana: revisar memoria libre y la otra región"
  severity            = 1
  frequency           = "PT5M"
  window_size         = "PT1H"

  criteria {
    metric_namespace = "Microsoft.Cache/redisEnterprise"
    metric_name      = "geoReplicationHealthy"
    aggregation      = "Minimum"
    operator         = "LessThan"
    threshold        = 1
  }

  action {
    action_group_id = azurerm_monitor_action_group.operaciones.id
  }
}

output "hostname" {
  description = "Nombre DNS (puerto 10000, TLS)"
  value       = azurerm_managed_redis.redis.hostname
}

output "puerto" {
  value = azurerm_managed_redis.redis.default_database[0].port
}

output "workspace_logs" {
  value = azurerm_log_analytics_workspace.log.id
}
