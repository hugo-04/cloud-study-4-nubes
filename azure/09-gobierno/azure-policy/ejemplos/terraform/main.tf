# Azure Policy como código (versión de estudio): guardarraíles NET-01…12 de ModaLima.
#   - 3 definiciones PERSONALIZADAS (desde ../json): etiqueta obligatoria, Service Bus sin acceso público, auditoría de diagnóstico
#   - 1 INICIATIVA que mezcla políticas integradas (por GUID) y las personalizadas
#   - 1 ASIGNACIÓN a la suscripción: empieza en modo "auditar" (enforce = false) y pasa a "bloquear" con una variable
#   - 1 asignación con efecto Modify (heredar la etiqueta env) con identidad + rol + tarea de remediación
#   - 1 EXENCIÓN con fecha de caducidad en un grupo de recursos de laboratorio
#   - Alerta del registro de actividad cuando alguien cambia una asignación o una exención
# En una organización real las asignaciones van en un GRUPO DE ADMINISTRACIÓN (ver ../../../grupos-de-administracion).
# terraform init && terraform plan   (los GUID de políticas integradas deben existir; confírmalos en el portal)

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

variable "bloquear" {
  description = "false = auditar (enforce=false y efecto Audit) · true = bloquear (enforce=true y efecto Deny)"
  type        = bool
  default     = false
}

variable "regiones_permitidas" {
  type    = list(string)
  default = ["eastus2", "centralus", "global"]
}

variable "etiquetas_obligatorias" {
  type    = list(string)
  default = ["owner", "env", "cost-center"]
}

variable "exclusiones" {
  description = "Alcances excluidos de la evaluación de la iniciativa (por ejemplo, un grupo de recursos de sandbox)"
  type        = list(string)
  default     = []
}

variable "correo_gobierno" {
  type    = string
  default = "gobierno@modalima.example"
}

variable "exencion_expira" {
  description = "Fecha de caducidad de la exención (RFC 3339)"
  type        = string
  default     = "2027-03-31T00:00:00Z"
}

data "azurerm_subscription" "actual" {}

locals {
  sub_id = data.azurerm_subscription.actual.id

  efecto = var.bloquear ? "Deny" : "Audit"

  integradas = "/providers/Microsoft.Authorization/policyDefinitions"

  # Políticas integradas (GUID verificados contra la documentación al escribir este ejemplo).
  # acepta_efecto = true  → la definición admite Audit/Deny/Disabled en el parámetro "effect".
  reglas_integradas = {
    "net02-nic-sin-ip-publica"        = { id = "83a86a26-fd1f-447c-b59d-e51f44264114", acepta_efecto = false }
    "net03-storage-sin-acceso-publ"   = { id = "b2982f36-99f2-4db5-8eff-283140c09693", acepta_efecto = true }
    "net03-cosmos-sin-acceso-publ"    = { id = "797b37f7-06b8-444c-b1ad-fc62867f335a", acepta_efecto = true }
    "net03-keyvault-sin-acceso-publ"  = { id = "405c5871-3e91-4644-8a63-58e19d68ff5b", acepta_efecto = true }
    "net03-sql-sin-acceso-publ"       = { id = "1b8ca024-1d5c-4dec-8995-b1a932b41780", acepta_efecto = true }
    "net03-eventhubs-sin-acceso-publ" = { id = "0602787f-9896-402a-a6e1-39ee63ee435e", acepta_efecto = true }
    "net05-cosmos-sin-claves"         = { id = "5450f5bd-9c72-4390-a9c4-a7aba4edfdd2", acepta_efecto = true }
    "net05-storage-sin-clave-comp"    = { id = "8c6a50c6-9ffd-4ae7-986f-5fa6111f9a54", acepta_efecto = true }
    "net05-eventhubs-sin-sas"         = { id = "5d4e3c65-4873-47be-94f3-6f8b953a3598", acepta_efecto = true }
    "net05-sql-solo-entra"            = { id = "b3a22bc9-66de-45fb-98fa-00f5df42f41a", acepta_efecto = true }
    "net06-subnets-privadas"          = { id = "7bca8353-aa3b-429b-904a-9229c4385837", acepta_efecto = true }
    "net01-subnets-con-nsg"           = { id = "e71308d3-144b-4262-b144-efdc3cc90517", acepta_efecto = false }
    "net08-flowlogs-por-vnet"         = { id = "4c3c6c5f-0d47-4402-99b8-aa543dd8bcee", acepta_efecto = false }
    "net10-puertos-de-admin-cerrados" = { id = "22730e10-96f6-4aac-ad84-9383d35b5917", acepta_efecto = false }
  }

  def_etiqueta   = jsondecode(file("${path.module}/../json/etiqueta-obligatoria.json")).properties
  def_servicebus = jsondecode(file("${path.module}/../json/servicebus-sin-acceso-publico.json")).properties
  def_diag_sb    = jsondecode(file("${path.module}/../json/auditar-diagnostico-servicebus.json")).properties
}

# ---------------------------------------------------------------------------
# 1) Definiciones personalizadas (se crean en la suscripción; mejor en un grupo de administración)
# ---------------------------------------------------------------------------
resource "azurerm_policy_definition" "etiqueta_obligatoria" {
  name         = "modalima-etiqueta-obligatoria"
  policy_type  = "Custom"
  mode         = local.def_etiqueta.mode
  display_name = local.def_etiqueta.displayName
  description  = local.def_etiqueta.description
  policy_rule  = jsonencode(local.def_etiqueta.policyRule)
  parameters   = jsonencode(local.def_etiqueta.parameters)
  metadata     = jsonencode(local.def_etiqueta.metadata)
}

resource "azurerm_policy_definition" "servicebus_sin_acceso_publico" {
  name         = "modalima-servicebus-sin-acceso-publico"
  policy_type  = "Custom"
  mode         = local.def_servicebus.mode
  display_name = local.def_servicebus.displayName
  description  = local.def_servicebus.description
  policy_rule  = jsonencode(local.def_servicebus.policyRule)
  parameters   = jsonencode(local.def_servicebus.parameters)
  metadata     = jsonencode(local.def_servicebus.metadata)
}

resource "azurerm_policy_definition" "servicebus_diagnostico" {
  name         = "modalima-servicebus-diagnostico"
  policy_type  = "Custom"
  mode         = local.def_diag_sb.mode
  display_name = local.def_diag_sb.displayName
  description  = local.def_diag_sb.description
  policy_rule  = jsonencode(local.def_diag_sb.policyRule)
  parameters   = jsonencode(local.def_diag_sb.parameters)
  metadata     = jsonencode(local.def_diag_sb.metadata)
}

# ---------------------------------------------------------------------------
# 2) Iniciativa: un paquete con parámetros comunes (efecto, regiones, etiquetas)
# ---------------------------------------------------------------------------
resource "azurerm_policy_set_definition" "guardarrailes" {
  name         = "modalima-guardarrailes-red-y-datos"
  policy_type  = "Custom"
  display_name = "ModaLima - Guardarraíles de red y datos (NET-01…12)"
  description  = "Reglas de red privada, sin claves, regiones y etiquetas. Ver catalogo-net-01-12.md."

  metadata = jsonencode({ category = "ModaLima", version = "1.0.0" })

  parameters = jsonencode({
    efecto = {
      type          = "String"
      allowedValues = ["Audit", "Deny", "Disabled"]
      defaultValue  = "Audit"
      metadata      = { displayName = "Efecto de las reglas que admiten Audit/Deny" }
    }
    regionesPermitidas = {
      type     = "Array"
      metadata = { displayName = "Regiones permitidas", strongType = "location" }
    }
  })

  # Políticas integradas
  dynamic "policy_definition_reference" {
    for_each = local.reglas_integradas
    content {
      reference_id         = policy_definition_reference.key
      policy_definition_id = "${local.integradas}/${policy_definition_reference.value.id}"
      parameter_values = policy_definition_reference.value.acepta_efecto ? jsonencode({
        effect = { value = "[parameters('efecto')]" }
      }) : null
    }
  }

  # NET-12: regiones permitidas (la definición integrada rechaza con Deny; el modo auditar se logra con enforce = false)
  policy_definition_reference {
    reference_id         = "net12-regiones-permitidas"
    policy_definition_id = "${local.integradas}/e56962a6-4747-49cd-b67b-bf8b01975c4c"
    parameter_values = jsonencode({
      listOfAllowedLocations = { value = "[parameters('regionesPermitidas')]" }
    })
  }

  # NET-12: etiquetas obligatorias (una referencia por etiqueta)
  dynamic "policy_definition_reference" {
    for_each = toset(var.etiquetas_obligatorias)
    content {
      reference_id         = "net12-etiqueta-${policy_definition_reference.value}"
      policy_definition_id = azurerm_policy_definition.etiqueta_obligatoria.id
      parameter_values = jsonencode({
        nombreEtiqueta = { value = policy_definition_reference.value }
        efecto         = { value = "[parameters('efecto')]" }
      })
    }
  }

  # NET-03: Service Bus (personalizada) y su diagnóstico
  policy_definition_reference {
    reference_id         = "net03-servicebus-sin-acceso-publ"
    policy_definition_id = azurerm_policy_definition.servicebus_sin_acceso_publico.id
    parameter_values = jsonencode({
      efecto = { value = "[parameters('efecto')]" }
    })
  }

  policy_definition_reference {
    reference_id         = "net08-servicebus-diagnostico"
    policy_definition_id = azurerm_policy_definition.servicebus_diagnostico.id
  }
}

# ---------------------------------------------------------------------------
# 3) Asignación: empieza en "auditar" (no bloquea) y pasa a "bloquear" con var.bloquear = true
# ---------------------------------------------------------------------------
resource "azurerm_subscription_policy_assignment" "guardarrailes" {
  name                 = "modalima-guardarrailes"
  display_name         = "ModaLima - Guardarraíles de red y datos"
  subscription_id      = local.sub_id
  policy_definition_id = azurerm_policy_set_definition.guardarrailes.id
  enforce              = var.bloquear
  not_scopes           = var.exclusiones

  parameters = jsonencode({
    efecto             = { value = local.efecto }
    regionesPermitidas = { value = var.regiones_permitidas }
  })

  non_compliance_message {
    content = "Este recurso incumple un guardarraíl de ModaLima (red privada, sin claves, región o etiquetas). Revisa catalogo-net-01-12.md o escribe a ${var.correo_gobierno}."
  }
}

# ---------------------------------------------------------------------------
# 4) Modify con identidad: heredar la etiqueta "env" del grupo de recursos + remediación de lo existente
# ---------------------------------------------------------------------------
resource "azurerm_subscription_policy_assignment" "heredar_env" {
  name                 = "modalima-heredar-env"
  display_name         = "ModaLima - Heredar la etiqueta env del grupo de recursos"
  subscription_id      = local.sub_id
  policy_definition_id = "${local.integradas}/ea3f2387-9b95-492a-a190-fcdc54f7b070"
  location             = var.ubicacion

  parameters = jsonencode({
    tagName = { value = "env" }
  })

  identity {
    type = "SystemAssigned"
  }
}

# Con Terraform/SDK/CLI los roles de la identidad se conceden A MANO (en el portal los concede el asistente).
# Usa el rol que figure en "roleDefinitionIds" de la definición (aquí: Contributor; confírmalo).
resource "azurerm_role_assignment" "heredar_env" {
  scope                = local.sub_id
  role_definition_name = "Contributor"
  principal_id         = azurerm_subscription_policy_assignment.heredar_env.identity[0].principal_id
}

resource "azurerm_subscription_policy_remediation" "heredar_env" {
  name                    = "remediar-heredar-env"
  subscription_id         = local.sub_id
  policy_assignment_id    = azurerm_subscription_policy_assignment.heredar_env.id
  resource_discovery_mode = "ExistingNonCompliant"

  depends_on = [azurerm_role_assignment.heredar_env]
}

# ---------------------------------------------------------------------------
# 5) Exención con fecha de caducidad (grupo de recursos de laboratorio)
# ---------------------------------------------------------------------------
resource "azurerm_resource_group" "laboratorio" {
  name     = "rg-laboratorio-politicas"
  location = var.ubicacion

  tags = {
    owner       = "plataforma"
    env         = "lab"
    cost-center = "cc-100"
  }
}

resource "azurerm_resource_group_policy_exemption" "laboratorio" {
  name                 = "lab-sin-acceso-publico-storage"
  display_name         = "Laboratorio: Storage con acceso público (temporal)"
  description          = "Necesario para la demostración del curso. Dueño: plataforma. Revisar antes de la fecha de caducidad."
  resource_group_id    = azurerm_resource_group.laboratorio.id
  policy_assignment_id = azurerm_subscription_policy_assignment.guardarrailes.id
  exemption_category   = "Waiver"
  expires_on           = var.exencion_expira

  # Solo exime esa regla de la iniciativa, no todas
  policy_definition_reference_ids = ["net03-storage-sin-acceso-publ"]
}

# ---------------------------------------------------------------------------
# 6) Alerta: alguien cambió o borró una asignación o una exención de políticas
# ---------------------------------------------------------------------------
resource "azurerm_resource_group" "gobierno" {
  name     = "rg-gobierno"
  location = var.ubicacion
}

resource "azurerm_monitor_action_group" "gobierno" {
  name                = "ag-gobierno"
  resource_group_name = azurerm_resource_group.gobierno.name
  short_name          = "gobierno"

  email_receiver {
    name                    = "equipo-gobierno"
    email_address           = var.correo_gobierno
    use_common_alert_schema = true
  }
}

resource "azurerm_monitor_activity_log_alert" "cambios_de_politicas" {
  for_each = {
    asignaciones = "Microsoft.Authorization/policyAssignments/write"
    borrado      = "Microsoft.Authorization/policyAssignments/delete"
    exenciones   = "Microsoft.Authorization/policyExemptions/write"
  }

  name                = "alerta-politicas-${each.key}"
  resource_group_name = azurerm_resource_group.gobierno.name
  location            = "global"
  scopes              = [local.sub_id]
  description         = "Se ejecutó ${each.value}"

  criteria {
    category       = "Administrative"
    operation_name = each.value
  }

  action {
    action_group_id = azurerm_monitor_action_group.gobierno.id
  }
}

output "iniciativa_id" {
  value = azurerm_policy_set_definition.guardarrailes.id
}

output "asignacion_id" {
  value = azurerm_subscription_policy_assignment.guardarrailes.id
}
