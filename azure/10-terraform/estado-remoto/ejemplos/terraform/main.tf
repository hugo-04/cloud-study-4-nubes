# Arranque (bootstrap) del estado remoto de Terraform en Azure.
# Se ejecuta UNA vez con estado local; luego se migra a sí mismo al backend (ver ../cli/estado.sh).
#
# Qué crea:
#   - Grupo de recursos dedicado al estado
#   - Cuenta de almacenamiento endurecida (sin claves, TLS 1.2, sin acceso público, firewall cerrado)
#   - Versionado y borrado suave de blobs y contenedores
#   - Contenedor "tfstate"
#   - Bloqueo CanNotDelete
#   - Roles de acceso al contenedor para las identidades de los pipelines
#   - (opcional) diagnóstico de lectura/escritura/borrado hacia Log Analytics

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

  subscription_id = var.subscription_id

  # El provider usa Entra ID (no claves de la cuenta) para las operaciones de datos del Storage,
  # por ejemplo crear el contenedor. Imprescindible con shared_access_key_enabled = false.
  storage_use_azuread = true
}

variable "subscription_id" {
  type        = string
  description = "Suscripción de plataforma donde vivirá el estado."
}

variable "ubicacion" {
  type        = string
  description = "Región de Azure."
  default     = "eastus2"
}

variable "prefijo" {
  type        = string
  description = "Prefijo corto de la organización, en minúsculas y sin guiones."
  default     = "modalima"

  validation {
    condition     = can(regex("^[a-z0-9]{2,10}$", var.prefijo))
    error_message = "El prefijo debe tener entre 2 y 10 letras minúsculas o números."
  }
}

variable "sufijo" {
  type        = string
  description = "Sufijo que vuelve único el nombre global de la cuenta (3 a 6 caracteres)."
  default     = "001"

  validation {
    condition     = can(regex("^[a-z0-9]{3,6}$", var.sufijo))
    error_message = "El sufijo debe tener entre 3 y 6 letras minúsculas o números."
  }
}

variable "ips_permitidas" {
  type        = list(string)
  description = "IP públicas (o rangos CIDR) desde las que se opera el estado, por ejemplo la salida de tus ejecutores."
  default     = []
}

variable "subredes_permitidas" {
  type        = list(string)
  description = "IDs de subredes (con el punto de servicio Microsoft.Storage) desde las que se opera el estado."
  default     = []
}

variable "accesos" {
  type = map(object({
    principal_id = string
    rol          = string
  }))
  description = "Quién puede leer/escribir el estado. Ej.: { apply = { principal_id = \"...\", rol = \"Storage Blob Data Owner\" } }"
  default     = {}
}

variable "workspace_log_analytics_id" {
  type        = string
  description = "ID del área de trabajo de Log Analytics para auditar el acceso al estado (opcional)."
  default     = null
}

variable "retencion_dias" {
  type        = number
  description = "Días de retención del borrado suave de blobs y contenedores."
  default     = 30
}

locals {
  nombre_cuenta = "st${var.prefijo}tfstate${var.sufijo}"

  etiquetas = {
    proposito = "estado-de-terraform"
    owner     = "plataforma"
    env       = "plataforma"
  }
}

resource "azurerm_resource_group" "estado" {
  name     = "rg-tfstate-${var.prefijo}"
  location = var.ubicacion
  tags     = local.etiquetas
}

resource "azurerm_storage_account" "estado" {
  name                = local.nombre_cuenta
  resource_group_name = azurerm_resource_group.estado.name
  location            = azurerm_resource_group.estado.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "ZRS"

  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  public_network_access_enabled   = true # el firewall de abajo cierra todo salvo lo permitido

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = var.retencion_dias
    }

    container_delete_retention_policy {
      days = var.retencion_dias
    }
  }

  network_rules {
    default_action             = "Deny"
    bypass                     = ["AzureServices"]
    ip_rules                   = var.ips_permitidas
    virtual_network_subnet_ids = var.subredes_permitidas
  }

  tags = local.etiquetas
}

resource "azurerm_storage_container" "estado" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.estado.id
  container_access_type = "private"
}

resource "azurerm_management_lock" "estado" {
  name       = "no-borrar-estado-de-terraform"
  scope      = azurerm_storage_account.estado.id
  lock_level = "CanNotDelete"
  notes      = "Contiene el estado de toda la infraestructura. Si se borra hay que reconstruirlo con import."
}

resource "azurerm_role_assignment" "acceso_al_estado" {
  for_each = var.accesos

  scope                = azurerm_storage_container.estado.resource_manager_id
  role_definition_name = each.value.rol
  principal_id         = each.value.principal_id
}

resource "azurerm_monitor_diagnostic_setting" "estado" {
  count = var.workspace_log_analytics_id == null ? 0 : 1

  name                       = "auditoria-del-estado"
  target_resource_id         = "${azurerm_storage_account.estado.id}/blobServices/default"
  log_analytics_workspace_id = var.workspace_log_analytics_id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }
}

output "configuracion_del_backend" {
  description = "Pega esto en backend.hcl (ver ../hcl/backend.hcl.ejemplo)."
  value = {
    resource_group_name  = azurerm_resource_group.estado.name
    storage_account_name = azurerm_storage_account.estado.name
    container_name       = azurerm_storage_container.estado.name
    use_azuread_auth     = true
  }
}
