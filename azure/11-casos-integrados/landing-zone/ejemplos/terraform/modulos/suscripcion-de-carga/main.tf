locals {
  sufijo = "${var.equipo}-${var.entorno}"
  etiquetas = {
    owner      = var.propietario
    env        = var.entorno
    team       = var.equipo
    costcenter = var.centro_de_costo
    managed-by = "terraform"
  }
}

# 1) La suscripción cuelga del grupo correcto: de aquí hereda políticas y roles
resource "azurerm_management_group_subscription_association" "esta" {
  provider            = azurerm.plataforma
  management_group_id = var.grupo_de_administracion_id
  subscription_id     = "/subscriptions/${var.subscription_id}"
}

# 2) Grupos de recursos base
resource "azurerm_resource_group" "red" {
  provider = azurerm.destino
  name     = "rg-red-${local.sufijo}"
  location = var.ubicacion
  tags     = local.etiquetas

  depends_on = [azurerm_management_group_subscription_association.esta]
}

resource "azurerm_resource_group" "carga" {
  provider = azurerm.destino
  name     = "rg-${local.sufijo}"
  location = var.ubicacion
  tags     = local.etiquetas

  depends_on = [azurerm_management_group_subscription_association.esta]
}

# 3) Red del equipo: una VNet con subredes derivadas del bloque asignado
resource "azurerm_virtual_network" "spoke" {
  provider            = azurerm.destino
  name                = "vnet-${local.sufijo}"
  resource_group_name = azurerm_resource_group.red.name
  location            = azurerm_resource_group.red.location
  address_space       = [var.cidr_red]
  tags                = local.etiquetas
}

resource "azurerm_subnet" "aplicacion" {
  provider             = azurerm.destino
  name                 = "snet-app"
  resource_group_name  = azurerm_resource_group.red.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [cidrsubnet(var.cidr_red, 2, 0)]
}

resource "azurerm_subnet" "datos" {
  provider             = azurerm.destino
  name                 = "snet-pe"
  resource_group_name  = azurerm_resource_group.red.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [cidrsubnet(var.cidr_red, 2, 1)]
}

# 4) Peering en las dos direcciones (la segunda se escribe en la suscripción de conectividad)
resource "azurerm_virtual_network_peering" "spoke_a_hub" {
  provider                  = azurerm.destino
  name                      = "peer-a-hub"
  resource_group_name       = azurerm_resource_group.red.name
  virtual_network_name      = azurerm_virtual_network.spoke.name
  remote_virtual_network_id = var.red_hub_id
  allow_forwarded_traffic   = true
  use_remote_gateways       = false
}

resource "azurerm_virtual_network_peering" "hub_a_spoke" {
  provider                  = azurerm.plataforma
  name                      = "peer-a-${local.sufijo}"
  resource_group_name       = var.red_hub_grupo_de_recursos
  virtual_network_name      = var.red_hub_nombre
  remote_virtual_network_id = azurerm_virtual_network.spoke.id
  allow_forwarded_traffic   = true
}

# 5) Registro de actividad de la suscripción hacia el espacio de trabajo central
resource "azurerm_monitor_diagnostic_setting" "actividad" {
  provider                   = azurerm.destino
  name                       = "actividad-a-central"
  target_resource_id         = "/subscriptions/${var.subscription_id}"
  log_analytics_workspace_id = var.workspace_central_id

  enabled_log {
    category = "Administrative"
  }
  enabled_log {
    category = "Security"
  }
  enabled_log {
    category = "Policy"
  }
}

# 6) Permisos: el equipo administra su grupo de recursos, pero solo ve el resto
resource "azurerm_role_assignment" "equipo_carga" {
  provider             = azurerm.destino
  scope                = azurerm_resource_group.carga.id
  role_definition_name = "Contributor"
  principal_id         = var.grupo_del_equipo
}

resource "azurerm_role_assignment" "equipo_lectura" {
  provider             = azurerm.destino
  scope                = "/subscriptions/${var.subscription_id}"
  role_definition_name = "Reader"
  principal_id         = var.grupo_del_equipo
}

# 7) Presupuesto con avisos reales y pronosticado
resource "azurerm_consumption_budget_subscription" "mensual" {
  provider        = azurerm.destino
  name            = "presupuesto-${local.sufijo}"
  subscription_id = "/subscriptions/${var.subscription_id}"
  amount          = var.presupuesto_mensual
  time_grain      = "Monthly"

  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00'Z'", plantimestamp())
  }

  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = var.correos_de_alerta
  }

  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThan"
    threshold_type = "Forecasted"
    contact_emails = var.correos_de_alerta
  }

  lifecycle {
    ignore_changes = [time_period]
  }
}

# 8) La red de producción no se borra por accidente
resource "azurerm_management_lock" "red" {
  provider   = azurerm.destino
  count      = var.entorno == "prod" ? 1 : 0
  name       = "no-borrar-red"
  scope      = azurerm_resource_group.red.id
  lock_level = "CanNotDelete"
  notes      = "Red compartida con el hub: borrar rompe la conectividad (solicitud de cambio obligatoria)."
}
