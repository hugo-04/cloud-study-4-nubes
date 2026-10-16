# App Service Linux (Java 21) con Terraform: plan, app, slot, identidad, VNet Integration,
# Private Endpoint y autoescalado.
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

resource "random_string" "sufijo" {
  length  = 5
  upper   = false
  special = false
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-estudio-appsvc"
  location = var.ubicacion
}

# ---------- Red ----------
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-compute"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.70.0.0/16"]
}

# Subred DELEGADA para la salida de la app (VNet Integration)
resource "azurerm_subnet" "integracion" {
  name                 = "snet-appsvc-int"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.70.1.0/26"]

  delegation {
    name = "serverfarms"

    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "pe" {
  name                 = "snet-pe"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.70.2.0/27"]
}

# ---------- Identidad ----------
resource "azurerm_user_assigned_identity" "app" {
  name                = "id-app-pedidos"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# ---------- Plan y app ----------
resource "azurerm_service_plan" "plan" {
  name                = "plan-modalima"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  os_type             = "Linux"
  sku_name            = "P0v3"
}

resource "azurerm_linux_web_app" "api" {
  name                = "app-modalima-${random_string.sufijo.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  service_plan_id     = azurerm_service_plan.plan.id

  https_only                                     = true
  client_affinity_enabled                        = false
  virtual_network_subnet_id                      = azurerm_subnet.integracion.id
  key_vault_reference_identity_id                = azurerm_user_assigned_identity.app.id
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app.id]
  }

  site_config {
    always_on                         = true
    http2_enabled                     = true
    ftps_state                        = "Disabled"
    minimum_tls_version               = "1.2"
    vnet_route_all_enabled            = true
    health_check_path                 = "/actuator/health/readiness"
    health_check_eviction_time_in_min = 5

    application_stack {
      java_server         = "JAVA"
      java_server_version = "21"
      java_version        = "21"
    }
  }

  app_settings = {
    AZURE_CLIENT_ID        = azurerm_user_assigned_identity.app.client_id
    SPRING_PROFILES_ACTIVE = "prod"
    JAVA_OPTS              = "-XX:MaxRAMPercentage=70 -XX:+ExitOnOutOfMemoryError -Dnetworkaddress.cache.ttl=30"
    # DB_PASSWORD = "@Microsoft.KeyVault(SecretUri=https://<tu-vault>.vault.azure.net/secrets/db-password/)"
  }

  sticky_settings {
    app_setting_names = ["APP_ENTORNO"]
  }
}

resource "azurerm_linux_web_app_slot" "staging" {
  name           = "staging"
  app_service_id = azurerm_linux_web_app.api.id
  https_only     = true

  site_config {
    always_on           = true
    ftps_state          = "Disabled"
    minimum_tls_version = "1.2"

    application_stack {
      java_server         = "JAVA"
      java_server_version = "21"
      java_version        = "21"
    }
  }

  app_settings = {
    WEBSITE_SWAP_WARMUP_PING_PATH     = "/actuator/health/readiness"
    WEBSITE_SWAP_WARMUP_PING_STATUSES = "200"
  }
}

# ---------- Entrada privada (opcional) ----------
resource "azurerm_private_dns_zone" "app" {
  name                = "privatelink.azurewebsites.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "app" {
  name                  = "link-vnet-compute"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.app.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

resource "azurerm_private_endpoint" "app" {
  name                = "pe-app"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.pe.id

  private_service_connection {
    name                           = "psc-app"
    private_connection_resource_id = azurerm_linux_web_app.api.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "zona-app"
    private_dns_zone_ids = [azurerm_private_dns_zone.app.id]
  }
}

# ---------- Autoescalado ----------
resource "azurerm_monitor_autoscale_setting" "plan" {
  name                = "autoscale-plan"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  target_resource_id  = azurerm_service_plan.plan.id

  profile {
    name = "por-cpu"

    capacity {
      default = 2
      minimum = 2
      maximum = 6
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.plan.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 70
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.plan.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT15M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 30
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
  }
}

output "url" {
  value = "https://${azurerm_linux_web_app.api.default_hostname}"
}
