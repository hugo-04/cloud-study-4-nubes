# Key Vault con Terraform: vault seguro, RBAC, secreto con expiración, clave con rotación,
# Private Endpoint con DNS privado y auditoría.
# terraform init && terraform plan   (OJO: con purge protection el vault queda reservado al destruir)

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

# El valor viene de fuera (variable de entorno TF_VAR_db_password); nunca escrito aquí
variable "db_password" {
  type      = string
  sensitive = true
}

variable "principal_id_app" {
  description = "principalId de la identidad de la aplicación (Managed Identity)"
  type        = string
}

resource "random_string" "sufijo" {
  length  = 6
  upper   = false
  special = false
}

data "azurerm_client_config" "actual" {}

resource "azurerm_resource_group" "rg" {
  name     = "rg-estudio-kv"
  location = var.ubicacion
}

# ---------- Red mínima para el Private Endpoint ----------
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-kv"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.60.0.0/16"]
}

resource "azurerm_subnet" "privado" {
  name                 = "snet-privado"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.60.1.0/24"]
}

# ---------- El vault ----------
resource "azurerm_key_vault" "kv" {
  name                = "kv-modalima-${random_string.sufijo.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tenant_id           = data.azurerm_client_config.actual.tenant_id
  sku_name            = "standard"

  rbac_authorization_enabled    = true
  purge_protection_enabled      = true
  soft_delete_retention_days    = 30
  public_network_access_enabled = true # ciérralo a false cuando el Private Endpoint ya funcione

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    ip_rules       = []
  }
}

# ---------- Permisos ----------
# Quien despliega necesita rol de DATOS para crear el secreto y la clave
resource "azurerm_role_assignment" "operador_secretos" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.actual.object_id
}

resource "azurerm_role_assignment" "operador_claves" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Crypto Officer"
  principal_id         = data.azurerm_client_config.actual.object_id
}

# La aplicación solo LEE secretos
resource "azurerm_role_assignment" "app_lee_secretos" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.principal_id_app
  principal_type       = "ServicePrincipal"
}

# ---------- Contenido ----------
resource "azurerm_key_vault_secret" "db_password" {
  name            = "db-password"
  value           = var.db_password
  key_vault_id    = azurerm_key_vault.kv.id
  content_type    = "text/plain"
  expiration_date = timeadd(timestamp(), "2160h") # ~90 días

  tags = {
    dueno   = "equipo-pedidos"
    entorno = "estudio"
  }

  depends_on = [azurerm_role_assignment.operador_secretos]

  lifecycle {
    ignore_changes = [expiration_date] # evita que timestamp() reescriba el secreto en cada plan
  }
}

resource "azurerm_key_vault_key" "reportes" {
  name         = "k-reportes"
  key_vault_id = azurerm_key_vault.kv.id
  key_type     = "RSA"
  key_size     = 3072
  key_opts     = ["wrapKey", "unwrapKey", "encrypt", "decrypt"]

  rotation_policy {
    automatic {
      time_after_creation = "P90D"
    }
    expire_after         = "P1Y"
    notify_before_expiry = "P30D"
  }

  depends_on = [azurerm_role_assignment.operador_claves]
}

# ---------- Private Endpoint + DNS privado ----------
resource "azurerm_private_dns_zone" "kv" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "kv" {
  name                  = "link-vnet-kv"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.kv.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

resource "azurerm_private_endpoint" "kv" {
  name                = "pe-kv"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.privado.id

  private_service_connection {
    name                           = "psc-kv"
    private_connection_resource_id = azurerm_key_vault.kv.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "zona-kv"
    private_dns_zone_ids = [azurerm_private_dns_zone.kv.id]
  }
}

# ---------- Auditoría ----------
resource "azurerm_log_analytics_workspace" "law" {
  name                = "law-estudio-kv"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_monitor_diagnostic_setting" "kv" {
  name                       = "diag-kv"
  target_resource_id         = azurerm_key_vault.kv.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  enabled_log {
    category = "AuditEvent"
  }
}

output "vault_uri" {
  value = azurerm_key_vault.kv.vault_uri
}
