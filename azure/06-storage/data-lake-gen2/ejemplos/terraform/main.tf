# Data Lake Storage Gen2 (cuenta con espacio de nombres jerárquico):
#   - Zonas medallion como sistemas de archivos: landing, bronze, silver, gold
#   - ACL por GRUPOS (acceso + por defecto) y roles de datos mínimos
#   - Private Endpoints de dfs y blob (los dos subrecursos) con sus zonas DNS privadas
#   - Ciclo de vida por zona; SFTP opcional con usuario local
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

variable "cerrar_red" {
  description = "true = firewall en Deny (el ejecutor de Terraform debe estar en la red o en ip_rules). false = solo para pruebas"
  type        = bool
  default     = false
}

variable "habilitar_sftp" {
  description = "SFTP cuesta por hora habilitado: solo si un socio lo necesita"
  type        = bool
  default     = false
}

variable "grupo_ingenieria_datos" {
  description = "Object id del grupo de Entra ID que escribe en silver/gold"
  type        = string
  default     = "00000000-0000-0000-0000-0000000000a1"
}

variable "grupo_analistas" {
  description = "Object id del grupo de Entra ID que lee gold"
  type        = string
  default     = "00000000-0000-0000-0000-0000000000a2"
}

variable "principal_pipelines" {
  description = "Object id de la identidad administrada de los pipelines de ingesta"
  type        = string
  default     = "00000000-0000-0000-0000-0000000000b1"
}

variable "llave_ssh_socio" {
  description = "Llave pública SSH del socio (solo si habilitar_sftp = true)"
  type        = string
  default     = "ssh-rsa AAAA-reemplazar"
}

locals {
  zonas = toset(["landing", "bronze", "silver", "gold"])

  # ACL de la RAÍZ de silver: los grupos necesitan 'x' (atravesar) para llegar a /ventas
  acl_raiz_silver = [
    { type = "user", id = null, permissions = "rwx" },
    { type = "group", id = null, permissions = "r-x" },
    { type = "mask", id = null, permissions = "rwx" },
    { type = "other", id = null, permissions = "---" },
    { type = "group", id = var.grupo_ingenieria_datos, permissions = "--x" },
    { type = "group", id = var.grupo_analistas, permissions = "--x" },
  ]
}

resource "random_string" "sufijo" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-estudio-lago"
  location = var.ubicacion
}

# ---------------------------------------------------------------- Red
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-lago"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  address_space       = ["10.50.0.0/16"]
}

resource "azurerm_subnet" "privado" {
  name                 = "snet-private-endpoints"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.50.2.0/24"]
}

resource "azurerm_private_dns_zone" "dfs" {
  name                = "privatelink.dfs.core.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "dfs" {
  name                  = "enlace-dfs"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.dfs.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                  = "enlace-blob"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

# ---------------------------------------------------------------- Cuenta con HNS
resource "azurerm_storage_account" "lago" {
  name                            = "stlago${random_string.sufijo.result}"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = "ZRS"
  is_hns_enabled                  = true # DECISIÓN DE DISEÑO: se fija al crear (migrar después es de ida)
  sftp_enabled                    = var.habilitar_sftp
  local_user_enabled              = var.habilitar_sftp
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true

  blob_properties {
    delete_retention_policy {
      days = 14
    }
    container_delete_retention_policy {
      days = 14
    }
  }

  network_rules {
    default_action = var.cerrar_red ? "Deny" : "Allow"
    bypass         = ["AzureServices"]
  }
}

resource "azurerm_private_endpoint" "dfs" {
  name                = "pe-lago-dfs"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  subnet_id           = azurerm_subnet.privado.id

  private_service_connection {
    name                           = "psc-lago-dfs"
    private_connection_resource_id = azurerm_storage_account.lago.id
    subresource_names              = ["dfs"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-dfs"
    private_dns_zone_ids = [azurerm_private_dns_zone.dfs.id]
  }
}

resource "azurerm_private_endpoint" "blob" {
  name                = "pe-lago-blob"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  subnet_id           = azurerm_subnet.privado.id

  private_service_connection {
    name                           = "psc-lago-blob"
    private_connection_resource_id = azurerm_storage_account.lago.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-blob"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }
}

# ---------------------------------------------------------------- Zonas (sistemas de archivos) con ACL por grupos
resource "azurerm_storage_data_lake_gen2_filesystem" "zona" {
  for_each           = local.zonas
  name               = each.key
  storage_account_id = azurerm_storage_account.lago.id

  dynamic "ace" {
    for_each = each.key == "silver" ? local.acl_raiz_silver : []
    content {
      type        = ace.value.type
      id          = ace.value.id
      permissions = ace.value.permissions
    }
  }
}

# Directorio de dominio en silver: ingeniería escribe, analistas leen; y por defecto para lo que se cree después.
# Ambos grupos tienen 'x' en la raíz de silver (arriba) para poder llegar hasta /ventas.
resource "azurerm_storage_data_lake_gen2_path" "silver_ventas" {
  path               = "ventas"
  filesystem_name    = azurerm_storage_data_lake_gen2_filesystem.zona["silver"].name
  storage_account_id = azurerm_storage_account.lago.id
  resource           = "directory"

  ace {
    type        = "user"
    permissions = "rwx"
  }
  ace {
    type        = "group"
    permissions = "r-x"
  }
  ace {
    type        = "mask"
    permissions = "rwx"
  }
  ace {
    type        = "other"
    permissions = "---"
  }
  ace {
    type        = "group"
    id          = var.grupo_ingenieria_datos
    permissions = "rwx"
  }
  ace {
    type        = "group"
    id          = var.grupo_ingenieria_datos
    permissions = "rwx"
    scope       = "default"
  }
  ace {
    type        = "group"
    id          = var.grupo_analistas
    permissions = "r-x"
  }
  ace {
    type        = "group"
    id          = var.grupo_analistas
    permissions = "r-x"
    scope       = "default"
  }
}

# ---------------------------------------------------------------- Roles de datos mínimos
# Pipelines: escriben en landing y bronze (rol solo en esos sistemas de archivos).
resource "azurerm_role_assignment" "pipelines" {
  for_each             = toset(["landing", "bronze"])
  scope                = "${azurerm_storage_account.lago.id}/blobServices/default/containers/${each.key}"
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.principal_pipelines
}

# OJO: NO se da rol de datos a nivel de cuenta a analistas/ingeniería: saltaría las ACL.

# ---------------------------------------------------------------- Ciclo de vida por zona
resource "azurerm_storage_management_policy" "ciclo" {
  storage_account_id = azurerm_storage_account.lago.id

  rule {
    name    = "tmp-fuera"
    enabled = true
    filters {
      prefix_match = ["landing/_tmp/", "bronze/_tmp/", "silver/_tmp/"]
      blob_types   = ["blockBlob"]
    }
    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = 2
      }
    }
  }

  rule {
    name    = "bronze-a-frio"
    enabled = true
    filters {
      prefix_match = ["bronze/"]
      blob_types   = ["blockBlob"]
    }
    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = 30
        tier_to_archive_after_days_since_modification_greater_than = 180
        delete_after_days_since_modification_greater_than          = 730
      }
    }
  }
}

# ---------------------------------------------------------------- SFTP opcional (usuario local aislado en landing/socios/cafeandino)
resource "azurerm_storage_account_local_user" "socio" {
  count = var.habilitar_sftp ? 1 : 0

  name                 = "cafeandino"
  storage_account_id   = azurerm_storage_account.lago.id
  home_directory       = "landing/socios/cafeandino"
  ssh_key_enabled      = true
  ssh_password_enabled = false # solo llaves

  ssh_authorized_key {
    description = "llave del socio"
    key         = var.llave_ssh_socio
  }

  permission_scope {
    service       = "blob"
    resource_name = azurerm_storage_data_lake_gen2_filesystem.zona["landing"].name

    permissions {
      read   = true
      write  = true
      create = true
      list   = true
      delete = false
    }
  }
}

output "cuenta" {
  value = azurerm_storage_account.lago.name
}

output "uri_abfss" {
  value = { for z in local.zonas : z => "abfss://${z}@${azurerm_storage_account.lago.name}.dfs.core.windows.net/" }
}
