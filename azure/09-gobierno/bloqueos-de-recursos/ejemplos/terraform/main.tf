# Bloqueos de recursos como código (versión de estudio) para ModaLima.
#   - Un grupo de recursos de producción con un bloqueo CanNotDelete (heredado por todo lo que contiene)
#   - Un recurso crítico (zona DNS privada) con su propio bloqueo
#   - Una variable "proteger" para poder quitar los bloqueos en un cambio revisado antes de destruir
#   - Rol personalizado "Administrador de bloqueos" (solo plataforma/seguridad) asignado a un grupo
#   - Alerta del registro de actividad cuando alguien CREA o BORRA un bloqueo
#   - Política DenyAction (borrado) para todo lo etiquetado env=prod, como segunda capa
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

variable "proteger" {
  description = "true = crear los bloqueos · false = quitarlos (primer paso de un borrado controlado, con revisión)"
  type        = bool
  default     = true
}

variable "objeto_plataforma" {
  description = "ID de objeto (Entra ID) del grupo de plataforma/seguridad que administrará los bloqueos"
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "correo_seguridad" {
  type    = string
  default = "seguridad@modalima.example"
}

data "azurerm_client_config" "actual" {}

data "azurerm_subscription" "actual" {}

# --- Recursos de ejemplo --------------------------------------------------------------------
resource "azurerm_resource_group" "datos_prod" {
  name     = "rg-modalima-prod-datos"
  location = var.ubicacion
  tags = {
    env         = "prod"
    owner       = "datos"
    cost-center = "cc-1200"
  }
}

resource "azurerm_private_dns_zone" "sql" {
  name                = "privatelink.database.windows.net"
  resource_group_name = azurerm_resource_group.datos_prod.name
  tags                = azurerm_resource_group.datos_prod.tags
}

# --- Bloqueo en el grupo de recursos: protege TODO lo que contiene (y lo que se cree después) -
resource "azurerm_management_lock" "grupo_datos" {
  count      = var.proteger ? 1 : 0
  name       = "lock-cannotdelete-rg-modalima-prod-datos"
  scope      = azurerm_resource_group.datos_prod.id
  lock_level = "CanNotDelete"
  notes      = "Producción de datos. Para borrar: ticket aprobado por plataforma. Dueño: equipo de datos."

  depends_on = [azurerm_private_dns_zone.sql]
}

# --- Bloqueo en un recurso concreto (más restrictivo que el del grupo si fuese ReadOnly) -----
resource "azurerm_management_lock" "dns_privada" {
  count      = var.proteger ? 1 : 0
  name       = "lock-cannotdelete-dns-sql"
  scope      = azurerm_private_dns_zone.sql.id
  lock_level = "CanNotDelete"
  notes      = "Si se borra, los Private Endpoints de SQL dejan de resolver. Dueño: plataforma de red."
}

# --- Rol personalizado: administrar bloqueos y NADA más --------------------------------------
resource "azurerm_role_definition" "admin_bloqueos" {
  name        = "ModaLima - Administrador de bloqueos"
  scope       = data.azurerm_subscription.actual.id
  description = "Crea y borra bloqueos de recursos. No puede desplegar ni modificar recursos."

  permissions {
    actions = [
      "Microsoft.Authorization/locks/*",
      "Microsoft.Resources/subscriptions/resourceGroups/read",
      "Microsoft.Resources/subscriptions/read",
    ]
    not_actions = []
  }

  assignable_scopes = [data.azurerm_subscription.actual.id]
}

resource "azurerm_role_assignment" "plataforma_bloqueos" {
  scope              = data.azurerm_subscription.actual.id
  role_definition_id = azurerm_role_definition.admin_bloqueos.role_definition_resource_id
  principal_id       = var.objeto_plataforma
}

# --- Alerta: alguien creó o borró un bloqueo ---------------------------------------------------
resource "azurerm_monitor_action_group" "seguridad" {
  name                = "ag-seguridad-bloqueos"
  resource_group_name = azurerm_resource_group.datos_prod.name
  short_name          = "segbloq"

  email_receiver {
    name          = "seguridad"
    email_address = var.correo_seguridad
  }
}

resource "azurerm_monitor_activity_log_alert" "bloqueo_borrado" {
  name                = "alerta-bloqueo-borrado"
  resource_group_name = azurerm_resource_group.datos_prod.name
  location            = "global"
  scopes              = [data.azurerm_subscription.actual.id]
  description         = "Un bloqueo de recursos fue borrado: puede ser el primer paso de un borrado."

  criteria {
    category       = "Administrative"
    operation_name = "Microsoft.Authorization/locks/delete"
  }

  action {
    action_group_id = azurerm_monitor_action_group.seguridad.id
  }
}

resource "azurerm_monitor_activity_log_alert" "bloqueo_creado" {
  name                = "alerta-bloqueo-creado"
  resource_group_name = azurerm_resource_group.datos_prod.name
  location            = "global"
  scopes              = [data.azurerm_subscription.actual.id]
  description         = "Se creó un bloqueo (revisar que sea el esperado)."

  criteria {
    category       = "Administrative"
    operation_name = "Microsoft.Authorization/locks/write"
  }

  action {
    action_group_id = azurerm_monitor_action_group.seguridad.id
  }
}

# --- Segunda capa: política DenyAction para todo lo etiquetado env=prod ------------------------
resource "azurerm_policy_definition" "no_borrar_prod" {
  name         = "modalima-no-borrar-prod"
  policy_type  = "Custom"
  mode         = "Indexed"
  display_name = "ModaLima - No permitir borrar recursos con env=prod"

  metadata = jsonencode({ category = "Gobierno" })

  policy_rule = jsonencode({
    if = {
      field  = "tags['env']"
      equals = "prod"
    }
    then = {
      effect = "denyAction"
      details = {
        actionNames = ["delete"]
      }
    }
  })
}

resource "azurerm_subscription_policy_assignment" "no_borrar_prod" {
  name                 = "modalima-no-borrar-prod"
  subscription_id      = data.azurerm_subscription.actual.id
  policy_definition_id = azurerm_policy_definition.no_borrar_prod.id
  display_name         = "No borrar recursos de producción"
  description          = "Segunda capa junto a los bloqueos. Para borrar: quitar la etiqueta con control de cambios."
  enforce              = true
}

output "bloqueos_activos" {
  value = var.proteger ? [
    azurerm_management_lock.grupo_datos[0].id,
    azurerm_management_lock.dns_privada[0].id,
  ] : []
}
