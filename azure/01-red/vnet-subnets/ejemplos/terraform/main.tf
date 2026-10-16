# Azure: VNet con subnets por capas + NAT Gateway.
# terraform init && terraform plan   (terraform destroy al terminar)

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
  # azurerm 4.x requiere ARM_SUBSCRIPTION_ID o el argumento subscription_id.
}

variable "ubicacion" {
  type    = string
  default = "eastus2"
}

locals {
  etiquetas = {
    env   = "estudio"
    owner = "hugo"
  }

  subnets = {
    web  = "10.10.0.0/24"
    app  = "10.10.1.0/24"
    data = "10.10.2.0/24"
    pe   = "10.10.9.0/27"
  }
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-estudio-red"
  location = var.ubicacion
  tags     = local.etiquetas
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-estudio"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.10.0.0/16"]
  tags                = local.etiquetas
}

resource "azurerm_subnet" "snet" {
  for_each = local.subnets

  name                 = "snet-${each.key}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [each.value]

  # Salida implicita desactivada: la salida se define con NAT Gateway.
  default_outbound_access_enabled = false
}

resource "azurerm_public_ip" "nat" {
  name                = "pip-nat"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.etiquetas
}

resource "azurerm_nat_gateway" "nat" {
  name                    = "natgw-estudio"
  location                = azurerm_resource_group.rg.location
  resource_group_name     = azurerm_resource_group.rg.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  tags                    = local.etiquetas
}

resource "azurerm_nat_gateway_public_ip_association" "nat" {
  nat_gateway_id       = azurerm_nat_gateway.nat.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "app" {
  subnet_id      = azurerm_subnet.snet["app"].id
  nat_gateway_id = azurerm_nat_gateway.nat.id
}

output "subnet_ids" {
  value = { for k, s in azurerm_subnet.snet : k => s.id }
}
