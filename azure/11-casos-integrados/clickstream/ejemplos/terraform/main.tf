terraform {
  required_version = ">= 1.5"
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
  type = string
}

variable "ubicacion" {
  type    = string
  default = "eastus2"
}

variable "entorno" {
  type = string
  validation {
    condition     = contains(["dev", "prod"], var.entorno)
    error_message = "entorno debe ser dev o prod."
  }
}

variable "particiones" {
  description = "Número de particiones del event hub. Decídelo con el planificador de capacidad: no se reduce y cambiarlo en Standard implica recrear."
  type        = number
  default     = 8
  validation {
    condition     = var.particiones >= 2 && var.particiones <= 32
    error_message = "Usa entre 2 y 32 particiones (verifica el límite de tu nivel)."
  }
}

variable "unidades_de_rendimiento" {
  type    = number
  default = 2
}

variable "maximo_auto_inflate" {
  description = "Tope de unidades al que puede crecer solo (control de costo)."
  type        = number
  default     = 6
}

variable "identidad_colector" {
  description = "Object ID de la identidad del servicio que publica los clics."
  type        = string
}

variable "identidad_agregador" {
  description = "Object ID de la identidad del servicio que agrega por minuto."
  type        = string
}

locals {
  etiquetas = { app = "clickstream", env = var.entorno, owner = "equipo-datos" }
}

resource "azurerm_resource_group" "clics" {
  name     = "rg-clics-${var.entorno}"
  location = var.ubicacion
  tags     = local.etiquetas
}

# Lago de datos (Data Lake Gen2 = cuenta con espacio de nombres jerárquico)
resource "azurerm_storage_account" "lago" {
  name                            = "stlagoclics${var.entorno}001"
  resource_group_name             = azurerm_resource_group.clics.name
  location                        = azurerm_resource_group.clics.location
  account_tier                    = "Standard"
  account_replication_type        = "ZRS"
  account_kind                    = "StorageV2"
  is_hns_enabled                  = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  tags                            = local.etiquetas
}

resource "azurerm_storage_container" "crudos" {
  name                  = "clics-crudos"
  storage_account_id    = azurerm_storage_account.lago.id
  container_access_type = "private"
}

# Puntos de control del procesador (qué particiones lee cada instancia y hasta dónde)
resource "azurerm_storage_account" "puntos" {
  name                            = "stptoclics${var.entorno}001"
  resource_group_name             = azurerm_resource_group.clics.name
  location                        = azurerm_resource_group.clics.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  tags                            = local.etiquetas
}

resource "azurerm_storage_container" "puntos" {
  name                  = "puntos-de-control"
  storage_account_id    = azurerm_storage_account.puntos.id
  container_access_type = "private"
}

resource "azurerm_eventhub_namespace" "clics" {
  name                          = "evhns-clics-${var.entorno}"
  resource_group_name           = azurerm_resource_group.clics.name
  location                      = azurerm_resource_group.clics.location
  sku                           = "Standard"
  capacity                      = var.unidades_de_rendimiento
  auto_inflate_enabled          = true
  maximum_throughput_units      = var.maximo_auto_inflate
  minimum_tls_version           = "1.2"
  local_authentication_enabled  = false # sin claves SAS del namespace: solo Entra ID
  public_network_access_enabled = true  # en producción: false + Private Endpoint (ver capítulo de red)
  tags                          = local.etiquetas

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_eventhub" "clics" {
  name              = "clics"
  namespace_id      = azurerm_eventhub_namespace.clics.id
  partition_count   = var.particiones
  message_retention = 3 # días (el máximo depende del nivel; verifica)

  capture_description {
    enabled             = true
    encoding            = "Avro"
    interval_in_seconds = 300
    size_limit_in_bytes = 314572800
    skip_empty_archives = true

    destination {
      name                = "EventHubArchive.AzureBlockBlob"
      archive_name_format = "{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}"
      blob_container_name = azurerm_storage_container.crudos.name
      storage_account_id  = azurerm_storage_account.lago.id
    }
  }
}

# Un grupo de consumidores por lector independiente: así no se pisan los puntos de control
resource "azurerm_eventhub_consumer_group" "agregador" {
  name                = "agregador"
  namespace_name      = azurerm_eventhub_namespace.clics.name
  eventhub_name       = azurerm_eventhub.clics.name
  resource_group_name = azurerm_resource_group.clics.name
}

resource "azurerm_eventhub_consumer_group" "reproceso" {
  name                = "reproceso"
  namespace_name      = azurerm_eventhub_namespace.clics.name
  eventhub_name       = azurerm_eventhub.clics.name
  resource_group_name = azurerm_resource_group.clics.name
}

# Permisos mínimos
resource "azurerm_role_assignment" "capture_escribe_lago" {
  scope                = azurerm_storage_account.lago.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_eventhub_namespace.clics.identity[0].principal_id
}

resource "azurerm_role_assignment" "colector_publica" {
  scope                = azurerm_eventhub.clics.id
  role_definition_name = "Azure Event Hubs Data Sender"
  principal_id         = var.identidad_colector
}

resource "azurerm_role_assignment" "agregador_lee" {
  scope                = azurerm_eventhub.clics.id
  role_definition_name = "Azure Event Hubs Data Receiver"
  principal_id         = var.identidad_agregador
}

resource "azurerm_role_assignment" "agregador_puntos" {
  scope                = azurerm_storage_container.puntos.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.identidad_agregador
}

output "espacio_de_nombres" {
  value = "${azurerm_eventhub_namespace.clics.name}.servicebus.windows.net"
}
