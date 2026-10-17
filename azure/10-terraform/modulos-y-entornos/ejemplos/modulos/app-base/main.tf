locals {
  nombre_cuenta = "st${var.nombre_aplicacion}${var.entorno}${var.sufijo}"

  etiquetas = merge(var.etiquetas, {
    aplicacion = var.nombre_aplicacion
    entorno    = var.entorno
    dueno      = var.dueno
    gestionado = "terraform"
  })
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.nombre_aplicacion}-${var.entorno}"
  location = var.ubicacion
  tags     = local.etiquetas
}

resource "azurerm_storage_account" "this" {
  name                = local.nombre_cuenta
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  account_tier             = "Standard"
  account_replication_type = var.replicacion
  account_kind             = "StorageV2"

  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false

  dynamic "network_rules" {
    for_each = var.restringir_red ? [1] : []

    content {
      default_action = "Deny"
      ip_rules       = var.ips_permitidas
      bypass         = ["AzureServices"]
    }
  }

  tags = local.etiquetas

  lifecycle {
    precondition {
      condition     = length(local.nombre_cuenta) <= 24
      error_message = "El nombre de la cuenta (st + aplicación + entorno + sufijo) no puede superar los 24 caracteres."
    }

    prevent_destroy = false # en producción: true (o un bloqueo CanNotDelete)
  }
}

resource "azurerm_storage_container" "this" {
  for_each = var.contenedores

  name                  = each.value
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "lectores" {
  for_each = var.lectores

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = each.value
}

check "cuenta_sin_claves" {
  assert {
    condition     = azurerm_storage_account.this.shared_access_key_enabled == false
    error_message = "La cuenta debe mantener desactivado el acceso por clave."
  }
}
