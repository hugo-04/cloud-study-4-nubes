# Red privada de la tienda: una VNet con subredes por función, zonas DNS privadas y un Private Endpoint
# por cada servicio de datos/mensajería. Los servicios (SQL, Key Vault, Blob, Service Bus) se crean en sus
# propios módulos/capítulos; aquí solo se CONECTAN a la red por su ID.
#
# Qué demuestra: el patrón repetido "PaaS sin acceso público + endpoint privado + zona DNS enlazada".

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
  description = "Suscripción de la zona de aterrizaje de la tienda."
}

variable "ubicacion" {
  type    = string
  default = "eastus2"
}

variable "entorno" {
  type    = string
  default = "prod"
}

variable "espacio_de_direcciones" {
  type        = string
  description = "CIDR de la VNet (planifícalo sin solapes con otras redes conectadas)."
  default     = "10.20.0.0/16"
}

variable "servicios_privados" {
  description = "Servicios a los que se les crea Private Endpoint: clave lógica => ID del recurso y subrecurso."
  type = map(object({
    recurso_id  = string
    subrecurso  = string # sqlServer, vault, blob, namespace…
    zona_dns    = string # privatelink.database.windows.net…
    descripcion = optional(string, "")
  }))
}

locals {
  etiquetas = {
    aplicacion = "tienda"
    entorno    = var.entorno
    gestionado = "terraform"
  }

  subredes = {
    apim = cidrsubnet(var.espacio_de_direcciones, 8, 1) # 10.20.1.0/24
    aks  = cidrsubnet(var.espacio_de_direcciones, 6, 1) # 10.20.4.0/22
    pe   = cidrsubnet(var.espacio_de_direcciones, 8, 8) # 10.20.8.0/24
  }

  zonas = toset([for k, s in var.servicios_privados : s.zona_dns])
}

resource "azurerm_resource_group" "red" {
  name     = "rg-tienda-red-${var.entorno}"
  location = var.ubicacion
  tags     = local.etiquetas
}

resource "azurerm_virtual_network" "tienda" {
  name                = "vnet-tienda-${var.entorno}"
  location            = azurerm_resource_group.red.location
  resource_group_name = azurerm_resource_group.red.name
  address_space       = [var.espacio_de_direcciones]
  tags                = local.etiquetas
}

resource "azurerm_subnet" "subredes" {
  for_each = local.subredes

  name                 = "snet-${each.key}"
  resource_group_name  = azurerm_resource_group.red.name
  virtual_network_name = azurerm_virtual_network.tienda.name
  address_prefixes     = [each.value]

  private_endpoint_network_policies = each.key == "pe" ? "Enabled" : "Disabled"
}

# NSG de la subred de endpoints privados: solo desde AKS y APIM, por los puertos de los servicios
resource "azurerm_network_security_group" "pe" {
  name                = "nsg-pe-${var.entorno}"
  location            = azurerm_resource_group.red.location
  resource_group_name = azurerm_resource_group.red.name
  tags                = local.etiquetas

  security_rule {
    name                       = "permitir-aks-a-servicios"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    source_address_prefix      = local.subredes.aks
    destination_address_prefix = local.subredes.pe
    destination_port_ranges    = ["443", "1433", "5432", "5671"]
  }

  security_rule {
    name                       = "negar-el-resto"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "pe" {
  subnet_id                 = azurerm_subnet.subredes["pe"].id
  network_security_group_id = azurerm_network_security_group.pe.id
}

# Una zona DNS privada por tipo de servicio, enlazada a la VNet
resource "azurerm_private_dns_zone" "zonas" {
  for_each = local.zonas

  name                = each.value
  resource_group_name = azurerm_resource_group.red.name
  tags                = local.etiquetas
}

resource "azurerm_private_dns_zone_virtual_network_link" "enlaces" {
  for_each = local.zonas

  name                  = "enlace-${replace(each.value, ".", "-")}"
  resource_group_name   = azurerm_resource_group.red.name
  private_dns_zone_name = azurerm_private_dns_zone.zonas[each.value].name
  virtual_network_id    = azurerm_virtual_network.tienda.id
  registration_enabled  = false
  tags                  = local.etiquetas
}

# Un Private Endpoint por servicio, con su registro DNS automático
resource "azurerm_private_endpoint" "servicios" {
  for_each = var.servicios_privados

  name                = "pe-${each.key}-${var.entorno}"
  location            = azurerm_resource_group.red.location
  resource_group_name = azurerm_resource_group.red.name
  subnet_id           = azurerm_subnet.subredes["pe"].id
  tags                = local.etiquetas

  private_service_connection {
    name                           = "psc-${each.key}"
    private_connection_resource_id = each.value.recurso_id
    subresource_names              = [each.value.subrecurso]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-${each.key}"
    private_dns_zone_ids = [azurerm_private_dns_zone.zonas[each.value.zona_dns].id]
  }
}

output "ips_privadas" {
  description = "IP privada de cada endpoint (para comprobar la resolución DNS desde dentro de la red)."
  value       = { for k, pe in azurerm_private_endpoint.servicios : k => pe.private_service_connection[0].private_ip_address }
}
