# Jerarquía de grupos de administración de ModaLima como código (versión de estudio).
#   - Raíz intermedia "mg-modalima" y la estructura plataforma / landing zones (corp, online) / sandbox / desmantelado
#   - Asociación de suscripciones a sus grupos (una sola fuente de verdad: la variable "suscripciones")
#   - Políticas por capas: regiones permitidas en la raíz intermedia; "sin IP pública" en Corp (modo auditar por defecto)
#   - RBAC solo para plataforma/seguridad (Reader en la raíz intermedia). Los equipos de carga NO reciben permisos aquí.
#   - Ajustes de la raíz del tenant (grupo predeterminado + exigir autorización) con AzAPI
#   - Rol "Hierarchy Settings Administrator" para el grupo de seguridad
# Requiere: acceso a la raíz del tenant para los ajustes (elevar acceso o rol sobre la raíz).
# terraform init && terraform plan

terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
  }
}

provider "azurerm" {
  features {}
  # Estas operaciones no usan una suscripción concreta, pero el proveedor exige una:
  # subscription_id = "<id de la suscripción de plataforma>"
}

provider "azapi" {}

variable "prefijo" {
  description = "Prefijo de la empresa para los ID de grupo (el ID no se puede cambiar después)"
  type        = string
  default     = "modalima"
}

variable "suscripciones" {
  description = "Suscripciones existentes y el grupo (clave de local.grupos) al que pertenecen"
  type = map(object({
    id    = string
    grupo = string
  }))
  default = {
    "sub-hub-red"        = { id = "00000000-0000-0000-0000-000000000001", grupo = "conectividad" }
    "sub-identidad"      = { id = "00000000-0000-0000-0000-000000000002", grupo = "identidad" }
    "sub-observabilidad" = { id = "00000000-0000-0000-0000-000000000003", grupo = "gestion" }
    "sub-tienda-prod"    = { id = "00000000-0000-0000-0000-000000000004", grupo = "corp" }
    "sub-pagos-prod"     = { id = "00000000-0000-0000-0000-000000000005", grupo = "corp" }
    "sub-web-publica"    = { id = "00000000-0000-0000-0000-000000000006", grupo = "online" }
    "sub-laboratorio-1"  = { id = "00000000-0000-0000-0000-000000000007", grupo = "sandbox" }
  }
}

variable "bloquear" {
  description = "false = las políticas solo auditan (DoNotEnforce) · true = bloquean (Enforce)"
  type        = bool
  default     = false
}

variable "regiones_permitidas" {
  type    = list(string)
  default = ["eastus2", "centralus", "global"]
}

variable "objeto_plataforma" {
  description = "ID de objeto (Entra ID) del grupo de plataforma: recibe Reader en la raíz intermedia"
  type        = string
  default     = "00000000-0000-0000-0000-0000000000a1"
}

variable "objeto_seguridad" {
  description = "ID de objeto (Entra ID) del grupo de seguridad: administra los ajustes de la jerarquía"
  type        = string
  default     = "00000000-0000-0000-0000-0000000000a2"
}

variable "aplicar_ajustes_de_raiz" {
  description = "true = cambiar el grupo predeterminado y exigir autorización (necesita acceso a la raíz del tenant)"
  type        = bool
  default     = false
}

data "azurerm_client_config" "actual" {}

# --- Jerarquía ---------------------------------------------------------------------------------
resource "azurerm_management_group" "raiz" {
  name         = "mg-${var.prefijo}"
  display_name = "ModaLima"
  # sin parent_management_group_id: cuelga de la raíz del tenant (Tenant Root Group)
}

resource "azurerm_management_group" "plataforma" {
  name                       = "mg-${var.prefijo}-plataforma"
  display_name               = "Plataforma"
  parent_management_group_id = azurerm_management_group.raiz.id
}

resource "azurerm_management_group" "identidad" {
  name                       = "mg-${var.prefijo}-identidad"
  display_name               = "Identidad"
  parent_management_group_id = azurerm_management_group.plataforma.id
}

resource "azurerm_management_group" "conectividad" {
  name                       = "mg-${var.prefijo}-conectividad"
  display_name               = "Conectividad"
  parent_management_group_id = azurerm_management_group.plataforma.id
}

resource "azurerm_management_group" "gestion" {
  name                       = "mg-${var.prefijo}-gestion"
  display_name               = "Gestión"
  parent_management_group_id = azurerm_management_group.plataforma.id
}

resource "azurerm_management_group" "landingzones" {
  name                       = "mg-${var.prefijo}-landingzones"
  display_name               = "Landing zones"
  parent_management_group_id = azurerm_management_group.raiz.id
}

resource "azurerm_management_group" "corp" {
  name                       = "mg-${var.prefijo}-corp"
  display_name               = "Corp (red privada)"
  parent_management_group_id = azurerm_management_group.landingzones.id
}

resource "azurerm_management_group" "online" {
  name                       = "mg-${var.prefijo}-online"
  display_name               = "Online (con entrada pública)"
  parent_management_group_id = azurerm_management_group.landingzones.id
}

resource "azurerm_management_group" "sandbox" {
  name                       = "mg-${var.prefijo}-sandbox"
  display_name               = "Sandbox"
  parent_management_group_id = azurerm_management_group.raiz.id
}

resource "azurerm_management_group" "desmantelado" {
  name                       = "mg-${var.prefijo}-desmantelado"
  display_name               = "Desmantelado"
  parent_management_group_id = azurerm_management_group.raiz.id
}

locals {
  grupos = {
    identidad    = azurerm_management_group.identidad.id
    conectividad = azurerm_management_group.conectividad.id
    gestion      = azurerm_management_group.gestion.id
    corp         = azurerm_management_group.corp.id
    online       = azurerm_management_group.online.id
    sandbox      = azurerm_management_group.sandbox.id
    desmantelado = azurerm_management_group.desmantelado.id
  }
}

# --- Suscripciones en su grupo (NO uses a la vez el atributo subscription_ids del grupo) -------------
resource "azurerm_management_group_subscription_association" "suscripciones" {
  for_each = var.suscripciones

  management_group_id = local.grupos[each.value.grupo]
  subscription_id     = "/subscriptions/${each.value.id}"
}

# --- Políticas por capas ---------------------------------------------------------------------------
# 1) Regiones permitidas en la raíz intermedia (aplica a todo ModaLima).
resource "azurerm_management_group_policy_assignment" "regiones" {
  name                 = "regiones-permitidas"
  display_name         = "Regiones permitidas de ModaLima"
  management_group_id  = azurerm_management_group.raiz.id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
  enforce              = var.bloquear

  parameters = jsonencode({
    listOfAllowedLocations = { value = var.regiones_permitidas }
  })
}

# 2) Corp: ninguna interfaz de red con IP pública (NET-02).
resource "azurerm_management_group_policy_assignment" "corp_sin_ip_publica" {
  name                 = "corp-sin-ip-publica"
  display_name         = "Corp: interfaces de red sin IP pública"
  management_group_id  = azurerm_management_group.corp.id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/83a86a26-fd1f-447c-b59d-e51f44264114"
  enforce              = var.bloquear
}

# --- RBAC: solo plataforma/seguridad. Los equipos de carga reciben permisos en SU suscripción. -----------
resource "azurerm_role_assignment" "plataforma_lectura" {
  scope                = azurerm_management_group.raiz.id
  role_definition_name = "Reader"
  principal_id         = var.objeto_plataforma
}

# --- Ajustes de la raíz del tenant (AzAPI) -----------------------------------------------------------
# El rol integrado "Hierarchy Settings Administrator" se asigna sobre la raíz del tenant.
data "azurerm_role_definition" "ajustes" {
  count = var.aplicar_ajustes_de_raiz ? 1 : 0
  name  = "Hierarchy Settings Administrator"
  scope = "/providers/Microsoft.Management/managementGroups/${data.azurerm_client_config.actual.tenant_id}"
}

resource "azurerm_role_assignment" "seguridad_ajustes" {
  count              = var.aplicar_ajustes_de_raiz ? 1 : 0
  scope              = "/providers/Microsoft.Management/managementGroups/${data.azurerm_client_config.actual.tenant_id}"
  role_definition_id = data.azurerm_role_definition.ajustes[0].id
  principal_id       = var.objeto_seguridad
}

resource "azapi_resource" "ajustes_de_jerarquia" {
  count     = var.aplicar_ajustes_de_raiz ? 1 : 0
  type      = "Microsoft.Management/managementGroups/settings@2021-04-01"
  name      = "default"
  parent_id = "/providers/Microsoft.Management/managementGroups/${data.azurerm_client_config.actual.tenant_id}"

  body = {
    properties = {
      defaultManagementGroup               = azurerm_management_group.sandbox.id
      requireAuthorizationForGroupCreation = true
    }
  }
}

output "grupos" {
  value = merge(local.grupos, { raiz = azurerm_management_group.raiz.id })
}
