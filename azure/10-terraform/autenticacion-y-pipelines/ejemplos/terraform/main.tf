# Identidades de los pipelines de Terraform, sin secretos (federación OIDC con GitHub Actions).
#
# Por cada entorno crea DOS identidades administradas asignadas por el usuario:
#   - plan  : solo lee la suscripción (Reader) y puede tomar el candado del estado.
#   - apply : puede cambiar recursos (Contributor) y asignar SOLO los roles que tú permitas.
# Cada identidad confía únicamente en los "subjects" de GitHub que declares para ella.
#
# Se ejecuta a mano (o desde un pipeline de plataforma) con una identidad que pueda crear roles.

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
}

variable "subscription_id" {
  type        = string
  description = "Suscripción donde viven las identidades (la de plataforma)."
}

variable "ubicacion" {
  type        = string
  description = "Región de Azure para las identidades."
  default     = "eastus2"
}

variable "issuer" {
  type        = string
  description = "Emisor de los tokens. Para GitHub Actions: https://token.actions.githubusercontent.com"
  default     = "https://token.actions.githubusercontent.com"
}

variable "plan_toma_el_candado" {
  type        = bool
  description = "true: la identidad de plan recibe Storage Blob Data Owner (toma el candado). false: solo lectura y el pipeline usa plan -lock=false."
  default     = true
}

variable "entornos" {
  description = "Un elemento por entorno. Los subjects deben coincidir EXACTO con lo que emite el pipeline."
  type = map(object({
    suscripcion_id      = string
    cuenta_de_estado_id = string
    contenedor          = optional(string, "tfstate")
    subjects_plan       = list(string)
    subjects_apply      = list(string)
    roles_delegables    = optional(list(string), [])
  }))

  validation {
    condition = alltrue(flatten([
      for k, e in var.entornos : [for s in concat(e.subjects_plan, e.subjects_apply) : length(s) <= 600 && !strcontains(s, "*")]
    ]))
    error_message = "Los subjects no admiten comodines y tienen un máximo de 600 caracteres."
  }

  validation {
    condition = alltrue([
      for k, e in var.entornos : length(e.subjects_plan) + length(e.subjects_apply) <= 10
    ])
    error_message = "Cada entorno crea 2 identidades y cada identidad admite 20 credenciales federadas; mantén pocos subjects."
  }
}

locals {
  identidades = merge(
    { for k, e in var.entornos : "${k}-plan" => { entorno = k, tipo = "plan", subjects = e.subjects_plan } },
    { for k, e in var.entornos : "${k}-apply" => { entorno = k, tipo = "apply", subjects = e.subjects_apply } },
  )

  credenciales = merge([
    for nombre, i in local.identidades : {
      for s in i.subjects : "${nombre}|${s}" => { identidad = nombre, subject = s }
    }
  ]...)

  # Roles integrados (GUID estables; verifica en la documentación de roles integrados).
  rol_rbac_admin = "f58310d9-a9f6-439a-9e8d-f62e7b41a168"

  # Condición ABAC: este administrador de RBAC solo puede asignar o quitar los roles de la lista.
  condicion = { for k, e in var.entornos : k => length(e.roles_delegables) == 0 ? null : join(" ", [
    "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR",
    "(@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${join(", ", e.roles_delegables)}}))",
    "AND",
    "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})) OR",
    "(@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${join(", ", e.roles_delegables)}}))",
  ]) }
}

resource "azurerm_resource_group" "identidades" {
  name     = "rg-identidades-terraform"
  location = var.ubicacion
}

resource "azurerm_user_assigned_identity" "tf" {
  for_each = local.identidades

  name                = "id-tf-${each.key}"
  resource_group_name = azurerm_resource_group.identidades.name
  location            = azurerm_resource_group.identidades.location
}

resource "azurerm_federated_identity_credential" "github" {
  for_each = local.credenciales

  name                = "gh-${replace(each.value.identidad, "|", "-")}-${substr(sha1(each.value.subject), 0, 8)}"
  resource_group_name = azurerm_resource_group.identidades.name
  parent_id           = azurerm_user_assigned_identity.tf[each.value.identidad].id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.issuer
  subject             = each.value.subject
}

# ---- Plan: lectura de la suscripción -------------------------------------------------
resource "azurerm_role_assignment" "plan_lector" {
  for_each = var.entornos

  scope                = "/subscriptions/${each.value.suscripcion_id}"
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.tf["${each.key}-plan"].principal_id
  principal_type       = "ServicePrincipal"
}

# ---- Apply: cambiar recursos ---------------------------------------------------------
resource "azurerm_role_assignment" "apply_colaborador" {
  for_each = var.entornos

  scope                = "/subscriptions/${each.value.suscripcion_id}"
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.tf["${each.key}-apply"].principal_id
  principal_type       = "ServicePrincipal"
}

# Contributor NO puede asignar roles. Si tu Terraform crea role assignments, dale este rol con condición.
resource "azurerm_role_assignment" "apply_rbac_acotado" {
  for_each = { for k, e in var.entornos : k => e if length(e.roles_delegables) > 0 }

  scope              = "/subscriptions/${each.value.suscripcion_id}"
  role_definition_id = "/subscriptions/${each.value.suscripcion_id}/providers/Microsoft.Authorization/roleDefinitions/${local.rol_rbac_admin}"
  principal_id       = azurerm_user_assigned_identity.tf["${each.key}-apply"].principal_id
  principal_type     = "ServicePrincipal"
  condition_version  = "2.0"
  condition          = local.condicion[each.key]
}

# ---- Estado: rol de DATOS sobre el contenedor ----------------------------------------
resource "azurerm_role_assignment" "estado_plan" {
  for_each = var.entornos

  scope                = "${each.value.cuenta_de_estado_id}/blobServices/default/containers/${each.value.contenedor}"
  role_definition_name = var.plan_toma_el_candado ? "Storage Blob Data Owner" : "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.tf["${each.key}-plan"].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "estado_apply" {
  for_each = var.entornos

  scope                = "${each.value.cuenta_de_estado_id}/blobServices/default/containers/${each.value.contenedor}"
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azurerm_user_assigned_identity.tf["${each.key}-apply"].principal_id
  principal_type       = "ServicePrincipal"
}

output "tenant_id" {
  value       = azurerm_user_assigned_identity.tf[keys(local.identidades)[0]].tenant_id
  description = "Va a la variable AZURE_TENANT_ID del repositorio."
}

output "client_ids" {
  description = "Un client_id por identidad: se guardan como VARIABLES (no son secretos) del entorno de GitHub."
  value       = { for k, i in azurerm_user_assigned_identity.tf : k => i.client_id }
}

output "subjects_confiados" {
  description = "Qué subject puede entrar como cada identidad (para revisarlo en el code review)."
  value       = { for k, i in local.identidades : k => i.subjects }
}
