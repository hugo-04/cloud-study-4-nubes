# Application Gateway for Containers (AGC) para un clúster AKS:
# subred delegada, recurso AGC, frontend, asociación e identidad del ALB Controller con Workload Identity.
# terraform init && terraform plan   (terraform destroy al terminar)
#
# Verifica el estado de los recursos azurerm_application_load_balancer* en tu versión del proveedor.

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

variable "aks_oidc_issuer_url" {
  description = "URL del emisor OIDC del clúster AKS (az aks show --query oidcIssuerProfile.issuerUrl)"
  type        = string
  default     = "https://eastus2.oic.prod-aks.azure.com/00000000-0000-0000-0000-000000000000/11111111-1111-1111-1111-111111111111/"
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-estudio-agc"
  location = var.ubicacion
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-agc"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.95.0.0/16"]
}

# Subred exclusiva para AGC: mínimo /24, delegada a Microsoft.ServiceNetworking/trafficControllers
resource "azurerm_subnet" "agc" {
  name                 = "snet-agc"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.95.1.0/24"]

  delegation {
    name = "agc"
    service_delegation {
      name    = "Microsoft.ServiceNetworking/trafficControllers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_application_load_balancer" "agc" {
  name                = "agc-modalima"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_application_load_balancer_frontend" "frontend" {
  name                         = "frontend-modalima"
  application_load_balancer_id = azurerm_application_load_balancer.agc.id
}

resource "azurerm_application_load_balancer_subnet_association" "asociacion" {
  name                         = "asociacion-agc"
  application_load_balancer_id = azurerm_application_load_balancer.agc.id
  subnet_id                    = azurerm_subnet.agc.id
}

# ---------- Identidad del ALB Controller (corre en el clúster) ----------
resource "azurerm_user_assigned_identity" "alb" {
  name                = "id-alb-controller"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_federated_identity_credential" "alb" {
  name                = "alb-controller"
  resource_group_name = azurerm_resource_group.rg.name
  parent_id           = azurerm_user_assigned_identity.alb.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.aks_oidc_issuer_url
  subject             = "system:serviceaccount:azure-alb-system:alb-controller-sa"
}

data "azurerm_role_definition" "config_manager" {
  name  = "AppGw for Containers Configuration Manager"
  scope = azurerm_resource_group.rg.id
}

resource "azurerm_role_assignment" "alb_config" {
  scope              = azurerm_application_load_balancer.agc.id
  role_definition_id = data.azurerm_role_definition.config_manager.id
  principal_id       = azurerm_user_assigned_identity.alb.principal_id
}

resource "azurerm_role_assignment" "alb_subred" {
  scope                = azurerm_subnet.agc.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.alb.principal_id
}

output "alb_id" {
  value = azurerm_application_load_balancer.agc.id
}

output "alb_client_id" {
  description = "Para el chart del ALB Controller (helm --set albController.podIdentity.clientID=...)"
  value       = azurerm_user_assigned_identity.alb.client_id
}
