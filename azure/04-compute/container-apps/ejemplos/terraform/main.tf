# Container Apps con Terraform: entorno, identidad, ACR sin contraseña, API con sondas y escala HTTP,
# secreto desde Key Vault, worker con escala a cero y un job programado.
# terraform init && terraform plan   (terraform destroy al terminar)
#
# Nota: azurerm no expone (todavía) la autenticación por identidad en las reglas KEDA personalizadas;
# para eso usa la CLI/YAML (ver ../cli) o el proveedor azapi. Verifica el estado del proveedor.

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

variable "key_vault_secret_id" {
  description = "URL del secreto en Key Vault (sin versión para tomar siempre la última)"
  type        = string
  default     = "https://kv-modalima-estudio01.vault.azure.net/secrets/db-password"
}

resource "random_string" "sufijo" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-estudio-aca"
  location = var.ubicacion
}

# ---------- Logs, ACR e identidad ----------
resource "azurerm_log_analytics_workspace" "law" {
  name                = "law-aca"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_container_registry" "acr" {
  name                = "acrmodalima${random_string.sufijo.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"
  admin_enabled       = false
}

resource "azurerm_user_assigned_identity" "app" {
  name                = "id-aca-api"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
  principal_type       = "ServicePrincipal"
}

# ---------- Entorno ----------
resource "azurerm_container_app_environment" "env" {
  name                       = "cae-modalima"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
}

# ---------- API ----------
resource "azurerm_container_app" "api" {
  name                         = "api-pedidos"
  container_app_environment_id = azurerm_container_app_environment.env.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Multiple"
  workload_profile_name        = "Consumption"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app.id]
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    identity = azurerm_user_assigned_identity.app.id
  }

  secret {
    name                = "db-password"
    key_vault_secret_id = var.key_vault_secret_id
    identity            = azurerm_user_assigned_identity.app.id
  }

  ingress {
    external_enabled = true
    target_port      = 8080
    transport        = "auto"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = 1
    max_replicas = 10

    http_scale_rule {
      name                = "http-50"
      concurrent_requests = "50"
    }

    container {
      name   = "api"
      image  = "mcr.microsoft.com/k8se/quickstart:latest" # reemplaza por tu imagen de ACR
      cpu    = 1.0
      memory = "2Gi"

      env {
        name        = "DB_PASSWORD"
        secret_name = "db-password"
      }

      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.app.client_id
      }

      env {
        name  = "JAVA_TOOL_OPTIONS"
        value = "-XX:MaxRAMPercentage=70 -XX:+ExitOnOutOfMemoryError"
      }

      startup_probe {
        transport               = "HTTP"
        port                    = 8080
        path                    = "/actuator/health/liveness"
        interval_seconds        = 5
        failure_count_threshold = 36
      }

      readiness_probe {
        transport               = "HTTP"
        port                    = 8080
        path                    = "/actuator/health/readiness"
        interval_seconds        = 10
        failure_count_threshold = 3
      }

      liveness_probe {
        transport               = "HTTP"
        port                    = 8080
        path                    = "/actuator/health/liveness"
        interval_seconds        = 10
        failure_count_threshold = 3
      }
    }
  }

  depends_on = [azurerm_role_assignment.acr_pull]
}

# ---------- Worker (escala a cero con una regla personalizada por cadena de conexión) ----------
# En producción prefiere autenticación por identidad (CLI/YAML/azapi) en lugar de cadenas.

# ---------- Job programado ----------
resource "azurerm_container_app_job" "reporte" {
  name                         = "job-reporte"
  location                     = azurerm_resource_group.rg.location
  resource_group_name          = azurerm_resource_group.rg.name
  container_app_environment_id = azurerm_container_app_environment.env.id

  replica_timeout_in_seconds = 1800
  replica_retry_limit        = 1

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app.id]
  }

  schedule_trigger_config {
    cron_expression          = "0 12 * * *"
    parallelism              = 1
    replica_completion_count = 1
  }

  template {
    container {
      name   = "reporte"
      image  = "mcr.microsoft.com/k8se/quickstart-jobs:latest"
      cpu    = 0.5
      memory = "1Gi"
    }
  }
}

output "api_fqdn" {
  value = azurerm_container_app.api.ingress[0].fqdn
}
