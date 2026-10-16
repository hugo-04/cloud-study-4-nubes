# AKS de producción con Terraform: VNet, ACR, Azure CNI Overlay + Cilium, Entra ID + Azure RBAC,
# 3 zonas, pool de usuario, KEDA, Key Vault CSI, Workload Identity, monitoreo y upgrades controlados.
# terraform init && terraform plan   (terraform destroy al terminar: los nodos cuestan por hora)

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

variable "grupo_admin_aks" {
  description = "objectId del grupo de Entra ID con permisos de administrador del clúster"
  type        = string
}

resource "random_string" "sufijo" {
  length  = 6
  upper   = false
  special = false
}

data "azurerm_client_config" "actual" {}

resource "azurerm_resource_group" "rg" {
  name     = "rg-estudio-aks"
  location = var.ubicacion
}

# ---------- Red ----------
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-aks"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.90.0.0/16"]
}

resource "azurerm_subnet" "nodos" {
  name                 = "snet-aks-nodos"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.90.0.0/22"]
}

# ---------- Registro de imágenes y logs ----------
resource "azurerm_container_registry" "acr" {
  name                = "acrmodalima${random_string.sufijo.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Premium"
  admin_enabled       = false
}

resource "azurerm_log_analytics_workspace" "law" {
  name                = "law-aks"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# ---------- Clúster ----------
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-modalima"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "aksmodalima"
  sku_tier            = "Standard"

  oidc_issuer_enabled       = true
  workload_identity_enabled = true
  local_account_disabled    = true

  automatic_upgrade_channel = "patch"
  node_os_upgrade_channel   = "NodeImage"

  identity {
    type = "SystemAssigned"
  }

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled     = true
    tenant_id              = data.azurerm_client_config.actual.tenant_id
    admin_group_object_ids = [var.grupo_admin_aks]
  }

  default_node_pool {
    name                         = "system"
    vm_size                      = "Standard_D2s_v5"
    vnet_subnet_id               = azurerm_subnet.nodos.id
    zones                        = ["1", "2", "3"]
    auto_scaling_enabled         = true
    min_count                    = 3
    max_count                    = 5
    only_critical_addons_enabled = true
    os_sku                       = "AzureLinux"

    upgrade_settings {
      max_surge = "33%"
    }
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    pod_cidr            = "192.168.0.0/16"
    service_cidr        = "172.16.0.0/16"
    dns_service_ip      = "172.16.0.10"
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
  }

  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  workload_autoscaler_profile {
    keda_enabled = true
  }

  monitor_metrics {}

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  }

  maintenance_window_auto_upgrade {
    frequency   = "Weekly"
    interval    = 1
    duration    = 4
    day_of_week = "Saturday"
    start_time  = "02:00"
    utc_offset  = "-05:00"
  }
}

# ---------- Pool de usuario ----------
resource "azurerm_kubernetes_cluster_node_pool" "userapi" {
  name                  = "userapi"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  mode                  = "User"
  vm_size               = "Standard_D4s_v5"
  vnet_subnet_id        = azurerm_subnet.nodos.id
  zones                 = ["1", "2", "3"]
  auto_scaling_enabled  = true
  min_count             = 2
  max_count             = 10
  os_sku                = "AzureLinux"

  node_labels = {
    carga = "api"
  }

  upgrade_settings {
    max_surge = "33%"
  }
}

# ---------- Permisos ----------
# Los nodos descargan imágenes del ACR con la identidad del kubelet
resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  principal_type       = "ServicePrincipal"
}

# La identidad del clúster necesita gestionar red en la subred que le diste
resource "azurerm_role_assignment" "red_cluster" {
  scope                = azurerm_subnet.nodos.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.aks.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

output "nombre_cluster" {
  value = azurerm_kubernetes_cluster.aks.name
}

output "oidc_issuer_url" {
  value = azurerm_kubernetes_cluster.aks.oidc_issuer_url
}

output "acr_login_server" {
  value = azurerm_container_registry.acr.login_server
}
