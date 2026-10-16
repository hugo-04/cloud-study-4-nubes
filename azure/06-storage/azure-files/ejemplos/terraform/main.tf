# Azure Files:
#   - Cuenta PREMIUM (FileStorage) con share SMB: SMB 3.1.1 + Kerberos, soft delete, red cerrada + Private Endpoint
#   - Cuenta aparte para NFS (NFS exige "secure transfer" desactivado -> solo por red privada)
#   - Roles por share (lectura/escritura SMB) y rol de datos para la app Java con SDK
#   - Azure Backup del share (instantánea diaria, retención 30 días)
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
  storage_use_azuread = true
}

variable "ubicacion" {
  type    = string
  default = "eastus2"
}

variable "principal_lectores" {
  description = "Object id del grupo que monta el share en solo lectura"
  type        = string
  default     = "00000000-0000-0000-0000-000000000001"
}

variable "principal_escritores" {
  description = "Object id del grupo/identidad que lee y escribe"
  type        = string
  default     = "00000000-0000-0000-0000-000000000002"
}

variable "principal_app_java" {
  description = "Object id de la identidad administrada de la app que usa el SDK por REST"
  type        = string
  default     = "00000000-0000-0000-0000-000000000003"
}

resource "random_string" "sufijo" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-estudio-files"
  location = var.ubicacion
}

# ---------------------------------------------------------------- Red
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-files"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  address_space       = ["10.40.0.0/16"]
}

resource "azurerm_subnet" "apps" {
  name                 = "snet-apps"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.40.1.0/24"]
  service_endpoints    = ["Microsoft.Storage"]
}

resource "azurerm_subnet" "privado" {
  name                 = "snet-private-endpoints"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.40.2.0/24"]
}

resource "azurerm_private_dns_zone" "file" {
  name                = "privatelink.file.core.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "file" {
  name                  = "enlace-vnet-files"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.file.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

# ---------------------------------------------------------------- Cuenta premium SMB
resource "azurerm_storage_account" "smb" {
  name                            = "stfsmb${random_string.sufijo.result}"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  account_kind                    = "FileStorage"
  account_tier                    = "Premium"
  account_replication_type        = "ZRS"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false # sin clave: solo identidad (los montajes con clave dejan de funcionar)
  default_to_oauth_authentication = true

  azure_files_authentication {
    directory_type = "AADKERB" # Microsoft Entra Kerberos: identidades híbridas
  }

  share_properties {
    retention_policy {
      days = 7 # soft delete del share
    }

    smb {
      versions                        = ["SMB3.1.1"]
      authentication_types            = ["Kerberos"]
      kerberos_ticket_encryption_type = ["AES-256"]
      channel_encryption_type         = ["AES-256-GCM"]
      multichannel_enabled            = true
    }
  }

  network_rules {
    default_action             = "Deny"
    bypass                     = ["AzureServices"] # Azure Backup y otros servicios de confianza
    virtual_network_subnet_ids = [azurerm_subnet.apps.id]
  }
}

resource "azurerm_storage_share" "contabilidad" {
  name               = "contabilidad"
  storage_account_id = azurerm_storage_account.smb.id
  quota              = 1024 # GiB: en premium la cuota ES rendimiento y costo
  enabled_protocol   = "SMB"
}

resource "azurerm_private_endpoint" "smb" {
  name                = "pe-files-smb"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  subnet_id           = azurerm_subnet.privado.id

  private_service_connection {
    name                           = "psc-files-smb"
    private_connection_resource_id = azurerm_storage_account.smb.id
    subresource_names              = ["file"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-files"
    private_dns_zone_ids = [azurerm_private_dns_zone.file.id]
  }
}

# Roles a nivel de SHARE (la segunda capa son las ACL NTFS dentro del share)
resource "azurerm_role_assignment" "lectores" {
  scope                = "${azurerm_storage_account.smb.id}/fileServices/default/fileshares/${azurerm_storage_share.contabilidad.name}"
  role_definition_name = "Storage File Data SMB Share Reader"
  principal_id         = var.principal_lectores
}

resource "azurerm_role_assignment" "escritores" {
  scope                = "${azurerm_storage_account.smb.id}/fileServices/default/fileshares/${azurerm_storage_share.contabilidad.name}"
  role_definition_name = "Storage File Data SMB Share Contributor"
  principal_id         = var.principal_escritores
}

# Aplicación Java con SDK por REST (intención de token "backup")
resource "azurerm_role_assignment" "app_java" {
  scope                = azurerm_storage_account.smb.id
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = var.principal_app_java
}

# ---------------------------------------------------------------- Azure Backup del share
# Verifica en la doc vigente la compatibilidad de Azure Backup con cuentas que tienen la clave compartida desactivada.
resource "azurerm_recovery_services_vault" "boveda" {
  name                = "rsv-files-${random_string.sufijo.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Standard"
  soft_delete_enabled = true
}

resource "azurerm_backup_policy_file_share" "diaria" {
  name                = "diaria-30-dias"
  resource_group_name = azurerm_resource_group.rg.name
  recovery_vault_name = azurerm_recovery_services_vault.boveda.name

  timezone = "UTC"

  backup {
    frequency = "Daily"
    time      = "02:00"
  }

  retention_daily {
    count = 30
  }
}

resource "azurerm_backup_container_storage_account" "cuenta" {
  resource_group_name = azurerm_resource_group.rg.name
  recovery_vault_name = azurerm_recovery_services_vault.boveda.name
  storage_account_id  = azurerm_storage_account.smb.id
}

resource "azurerm_backup_protected_file_share" "contabilidad" {
  resource_group_name       = azurerm_resource_group.rg.name
  recovery_vault_name       = azurerm_recovery_services_vault.boveda.name
  source_storage_account_id = azurerm_backup_container_storage_account.cuenta.storage_account_id
  source_file_share_name    = azurerm_storage_share.contabilidad.name
  backup_policy_id          = azurerm_backup_policy_file_share.diaria.id
}

# ---------------------------------------------------------------- Cuenta aparte para NFS
resource "azurerm_storage_account" "nfs" {
  name                            = "stfnfs${random_string.sufijo.result}"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  account_kind                    = "FileStorage"
  account_tier                    = "Premium"
  account_replication_type        = "LRS"
  https_traffic_only_enabled      = false # requisito del protocolo NFS sin TLS nativo
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false

  network_rules {
    default_action             = "Deny" # NFS solo por red privada / service endpoint
    virtual_network_subnet_ids = [azurerm_subnet.apps.id]
  }
}

resource "azurerm_storage_share" "datos_nfs" {
  name               = "datos-compartidos"
  storage_account_id = azurerm_storage_account.nfs.id
  quota              = 100
  enabled_protocol   = "NFS"
}

output "cuenta_smb" {
  value = azurerm_storage_account.smb.name
}

output "cuenta_nfs" {
  value = azurerm_storage_account.nfs.name
}
