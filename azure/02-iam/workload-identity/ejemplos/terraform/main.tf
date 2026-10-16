# Workload Identity en AKS con Terraform: clúster con OIDC, identidad, credencial federada y rol.
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
}

variable "ubicacion" {
  type    = string
  default = "eastus2"
}

variable "namespace" {
  type    = string
  default = "modalima"
}

variable "service_account" {
  type    = string
  default = "sa-api"
}

resource "random_string" "sufijo" {
  length  = 6
  upper   = false
  special = false
}

data "azurerm_client_config" "actual" {}

resource "azurerm_resource_group" "rg" {
  name     = "rg-estudio-wi"
  location = var.ubicacion
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-estudio-wi"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "aksestudiowi"

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  default_node_pool {
    name       = "system"
    node_count = 1
    vm_size    = "Standard_B2s"
  }

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_user_assigned_identity" "api" {
  name                = "id-api-pedidos"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Confia en el ServiceAccount EXACTO del clúster
resource "azurerm_federated_identity_credential" "api" {
  name                = "fc-api"
  resource_group_name = azurerm_resource_group.rg.name
  parent_id           = azurerm_user_assigned_identity.api.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  subject             = "system:serviceaccount:${var.namespace}:${var.service_account}"
}

resource "azurerm_key_vault" "kv" {
  name                       = "kv-wi-${random_string.sufijo.result}"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  tenant_id                  = data.azurerm_client_config.actual.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
}

resource "azurerm_role_assignment" "api_lee_secretos" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.api.principal_id
  principal_type       = "ServicePrincipal"
}

output "client_id_para_la_anotacion" {
  value = azurerm_user_assigned_identity.api.client_id
}
