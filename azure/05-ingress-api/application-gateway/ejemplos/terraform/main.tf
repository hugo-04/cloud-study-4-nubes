# Application Gateway WAF_v2 completo:
#  - subred dedicada + NSG con las reglas obligatorias (GatewayManager, AzureLoadBalancer, 80/443)
#  - IP pública Standard con zonas, identidad para leer el certificado de Key Vault (sin versión → rota solo)
#  - política WAF (Detection al inicio), listener HTTPS, redirección HTTP→HTTPS, sonda y backend App Service
#  - diagnósticos hacia Log Analytics
# terraform init && terraform plan   (terraform destroy al terminar: el gateway cuesta por hora)

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

variable "key_vault_id" {
  description = "Id del Key Vault que contiene el certificado"
  type        = string
  default     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-estudio-kv/providers/Microsoft.KeyVault/vaults/kv-modalima-estudio01"
}

variable "certificado_secret_id" {
  description = "URL del secreto del certificado SIN versión (rotación automática)"
  type        = string
  default     = "https://kv-modalima-estudio01.vault.azure.net/secrets/cert-api"
}

variable "backend_fqdn" {
  description = "FQDN del backend (App Service con Private Endpoint o público restringido al gateway)"
  type        = string
  default     = "app-pedidos-modalima.azurewebsites.net"
}

variable "dominio" {
  type    = string
  default = "api.modalima.example"
}

locals {
  nombre = "modalima"
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-estudio-agw"
  location = var.ubicacion
}

# ---------- Red ----------
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-agw"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.96.0.0/16"]
}

resource "azurerm_subnet" "agw" {
  name                 = "snet-agw" # DEDICADA: nada más vive aquí
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.96.0.0/24"]
}

resource "azurerm_network_security_group" "agw" {
  name                = "nsg-agw"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "permitir-gatewaymanager"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "65200-65535" # OBLIGATORIO en v2
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "permitir-azure-load-balancer"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "permitir-web-internet"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "agw" {
  subnet_id                 = azurerm_subnet.agw.id
  network_security_group_id = azurerm_network_security_group.agw.id
}

resource "azurerm_public_ip" "agw" {
  name                = "pip-agw-${local.nombre}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
}

# ---------- Identidad para leer el certificado ----------
resource "azurerm_user_assigned_identity" "agw" {
  name                = "id-agw-${local.nombre}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_role_assignment" "agw_kv" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.agw.principal_id
}

# ---------- Política WAF ----------
resource "azurerm_web_application_firewall_policy" "waf" {
  name                = "waf-${local.nombre}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  policy_settings {
    enabled                     = true
    mode                        = "Detection" # pasa a "Prevention" tras medir falsos positivos
    request_body_check          = true
    max_request_body_size_in_kb = 128
    file_upload_limit_in_mb     = 100
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }

    # Ejemplo de exclusión precisa para un falso positivo (campo "comentario" del cuerpo)
    exclusion {
      match_variable          = "RequestArgNames"
      selector                = "comentario"
      selector_match_operator = "Equals"
    }
  }

  # Regla personalizada: limitar tasa por IP de cliente
  custom_rules {
    name      = "LimiteTasaPorIP"
    priority  = 10
    rule_type = "RateLimitRule"
    action    = "Block"

    rate_limit_duration  = "OneMin"
    rate_limit_threshold = 300
    group_rate_limit_by  = "ClientAddr"

    match_conditions {
      match_variables {
        variable_name = "RequestUri"
      }
      operator           = "Contains"
      negation_condition = false
      match_values       = ["/"]
    }
  }
}

# ---------- Application Gateway ----------
locals {
  frontend_ip_publica = "ip-publica"
  puerto_https        = "puerto-443"
  puerto_http         = "puerto-80"
  pool                = "pool-pedidos"
  settings            = "settings-pedidos"
  sonda               = "sonda-pedidos"
  listener_https      = "listener-https"
  listener_http       = "listener-http"
  certificado         = "cert-api"
  redireccion         = "http-a-https"
}

resource "azurerm_application_gateway" "agw" {
  name                = "agw-${local.nombre}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  zones               = ["1", "2", "3"]
  firewall_policy_id  = azurerm_web_application_firewall_policy.waf.id

  sku {
    name = "WAF_v2"
    tier = "WAF_v2"
  }

  autoscale_configuration {
    min_capacity = 2
    max_capacity = 10
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.agw.id]
  }

  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101S" # TLS 1.2+; verifica la política vigente
  }

  gateway_ip_configuration {
    name      = "gw-ip"
    subnet_id = azurerm_subnet.agw.id
  }

  frontend_ip_configuration {
    name                 = local.frontend_ip_publica
    public_ip_address_id = azurerm_public_ip.agw.id
  }

  frontend_port {
    name = local.puerto_https
    port = 443
  }

  frontend_port {
    name = local.puerto_http
    port = 80
  }

  ssl_certificate {
    name                = local.certificado
    key_vault_secret_id = var.certificado_secret_id # sin versión → el gateway la relee solo
  }

  backend_address_pool {
    name  = local.pool
    fqdns = [var.backend_fqdn]
  }

  probe {
    name                                      = local.sonda
    protocol                                  = "Https"
    path                                      = "/actuator/health/readiness"
    interval                                  = 15
    timeout                                   = 5
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = true

    match {
      status_code = ["200"]
    }
  }

  backend_http_settings {
    name                                = local.settings
    protocol                            = "Https"
    port                                = 443
    cookie_based_affinity               = "Disabled"
    request_timeout                     = 30
    pick_host_name_from_backend_address = true # el App Service enruta por su nombre
    probe_name                          = local.sonda
    connection_draining {
      enabled           = true
      drain_timeout_sec = 30
    }
  }

  http_listener {
    name                           = local.listener_https
    frontend_ip_configuration_name = local.frontend_ip_publica
    frontend_port_name             = local.puerto_https
    protocol                       = "Https"
    host_names                     = [var.dominio]
    ssl_certificate_name           = local.certificado
    require_sni                    = true
  }

  http_listener {
    name                           = local.listener_http
    frontend_ip_configuration_name = local.frontend_ip_publica
    frontend_port_name             = local.puerto_http
    protocol                       = "Http"
  }

  redirect_configuration {
    name                 = local.redireccion
    redirect_type        = "Permanent"
    target_listener_name = local.listener_https
    include_path         = true
    include_query_string = true
  }

  request_routing_rule {
    name                        = "regla-http-redirige"
    rule_type                   = "Basic"
    priority                    = 100
    http_listener_name          = local.listener_http
    redirect_configuration_name = local.redireccion
  }

  request_routing_rule {
    name                       = "regla-https-pedidos"
    rule_type                  = "Basic"
    priority                   = 110
    http_listener_name         = local.listener_https
    backend_address_pool_name  = local.pool
    backend_http_settings_name = local.settings
  }

  depends_on = [azurerm_role_assignment.agw_kv]
}

# ---------- Diagnósticos ----------
resource "azurerm_log_analytics_workspace" "law" {
  name                = "law-agw"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_monitor_diagnostic_setting" "agw" {
  name                       = "diag-agw"
  target_resource_id         = azurerm_application_gateway.agw.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  enabled_log {
    category = "ApplicationGatewayAccessLog"
  }

  enabled_log {
    category = "ApplicationGatewayFirewallLog"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

output "ip_publica" {
  value = azurerm_public_ip.agw.ip_address
}
