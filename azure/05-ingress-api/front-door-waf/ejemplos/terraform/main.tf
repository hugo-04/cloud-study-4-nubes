# Azure Front Door Premium con WAF:
#  perfil, endpoint, grupo de orígenes con sonda HEAD, dos orígenes (principal y respaldo con prioridad 2),
#  ruta, reglas (cabeceras de seguridad), política WAF (Detection) enlazada con el endpoint y dominio personalizado.
# terraform init && terraform plan   (terraform destroy al terminar: Premium cuesta por perfil)
#
# Cierra el origen: restricción por etiqueta AzureFrontDoor.Backend + validar X-Azure-FDID (var.frontdoor_id en la app),
# o Private Link (bloque private_link del origen, requiere aprobar la conexión en el recurso de origen).

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

variable "origen_principal" {
  description = "Host del origen principal"
  type        = string
  default     = "app-pedidos-modalima.azurewebsites.net"
}

variable "origen_respaldo" {
  description = "Host del origen de respaldo (otra región)"
  type        = string
  default     = "app-pedidos-modalima-br.azurewebsites.net"
}

variable "dominio" {
  type    = string
  default = "api.modalima.example"
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-estudio-afd"
  location = var.ubicacion
}

resource "azurerm_cdn_frontdoor_profile" "afd" {
  name                = "afd-modalima"
  resource_group_name = azurerm_resource_group.rg.name
  sku_name            = "Premium_AzureFrontDoor"
}

resource "azurerm_cdn_frontdoor_endpoint" "ep" {
  name                     = "ep-modalima"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.afd.id
}

# ---------- Orígenes ----------
resource "azurerm_cdn_frontdoor_origin_group" "og" {
  name                     = "og-pedidos"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.afd.id

  session_affinity_enabled = false

  load_balancing {
    sample_size                        = 4
    successful_samples_required        = 3
    additional_latency_in_milliseconds = 50
  }

  health_probe {
    path                = "/livez" # ligera, sin autenticación
    request_type        = "HEAD"
    protocol            = "Https"
    interval_in_seconds = 60
  }
}

resource "azurerm_cdn_frontdoor_origin" "principal" {
  name                          = "principal"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.og.id
  enabled                       = true

  host_name                      = var.origen_principal
  origin_host_header             = var.origen_principal
  http_port                      = 80
  https_port                     = 443
  certificate_name_check_enabled = true
  priority                       = 1
  weight                         = 100
}

resource "azurerm_cdn_frontdoor_origin" "respaldo" {
  name                          = "respaldo"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.og.id
  enabled                       = true

  host_name                      = var.origen_respaldo
  origin_host_header             = var.origen_respaldo
  http_port                      = 80
  https_port                     = 443
  certificate_name_check_enabled = true
  priority                       = 2 # solo recibe tráfico si el de prioridad 1 no está sano
  weight                         = 100
}

# ---------- Reglas: cabeceras de seguridad ----------
resource "azurerm_cdn_frontdoor_rule_set" "reglas" {
  name                     = "reglasseguridad"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.afd.id
}

resource "azurerm_cdn_frontdoor_rule" "hsts" {
  name                      = "hsts"
  cdn_frontdoor_rule_set_id = azurerm_cdn_frontdoor_rule_set.reglas.id
  order                     = 1
  behavior_on_match         = "Continue"

  actions {
    response_header_action {
      header_action = "Overwrite"
      header_name   = "Strict-Transport-Security"
      value         = "max-age=31536000; includeSubDomains"
    }
  }
}

# ---------- Dominio personalizado (certificado gestionado) ----------
resource "azurerm_cdn_frontdoor_custom_domain" "dominio" {
  name                     = "api-modalima"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.afd.id
  host_name                = var.dominio

  tls {
    certificate_type    = "ManagedCertificate"
    minimum_tls_version = "TLS12"
  }
}

# ---------- Ruta ----------
resource "azurerm_cdn_frontdoor_route" "api" {
  name                          = "ruta-api"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.ep.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.og.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.principal.id, azurerm_cdn_frontdoor_origin.respaldo.id]
  cdn_frontdoor_rule_set_ids    = [azurerm_cdn_frontdoor_rule_set.reglas.id]

  enabled                = true
  forwarding_protocol    = "HttpsOnly"
  https_redirect_enabled = true
  patterns_to_match      = ["/*"]
  supported_protocols    = ["Http", "Https"]

  cdn_frontdoor_custom_domain_ids = [azurerm_cdn_frontdoor_custom_domain.dominio.id]
  link_to_default_domain          = false

  # Sin bloque "cache": las APIs dinámicas NO se cachean. Para estáticos crea otra ruta con
  # patterns_to_match = ["/static/*"] y un bloque cache { query_string_caching_behavior = "IgnoreQueryString" ... }.
}

resource "azurerm_cdn_frontdoor_custom_domain_association" "asociacion" {
  cdn_frontdoor_custom_domain_id = azurerm_cdn_frontdoor_custom_domain.dominio.id
  cdn_frontdoor_route_ids        = [azurerm_cdn_frontdoor_route.api.id]
}

# ---------- WAF ----------
resource "azurerm_cdn_frontdoor_firewall_policy" "waf" {
  name                = "wafmodalima"
  resource_group_name = azurerm_resource_group.rg.name
  sku_name            = azurerm_cdn_frontdoor_profile.afd.sku_name
  enabled             = true
  mode                = "Detection" # a "Prevention" tras medir falsos positivos

  managed_rule {
    type    = "Microsoft_DefaultRuleSet"
    version = "2.1"
    action  = "Block"
  }

  managed_rule {
    type    = "Microsoft_BotManagerRuleSet"
    version = "1.1"
    action  = "Block"
  }

  custom_rule {
    name                           = "LimiteTasa"
    enabled                        = true
    priority                       = 10
    type                           = "RateLimitRule"
    action                         = "Block"
    rate_limit_duration_in_minutes = 1
    rate_limit_threshold           = 300

    match_condition {
      match_variable     = "RequestUri"
      operator           = "Contains"
      negation_condition = false
      match_values       = ["/api/"]
    }
  }

  custom_rule {
    name     = "BloquearPaises"
    enabled  = false # actívala si el negocio solo opera en ciertos países
    priority = 20
    type     = "MatchRule"
    action   = "Block"

    match_condition {
      match_variable     = "SocketAddr"
      operator           = "GeoMatch"
      negation_condition = true
      match_values       = ["PE", "CO", "CL", "MX", "US"]
    }
  }
}

resource "azurerm_cdn_frontdoor_security_policy" "seguridad" {
  name                     = "seguridad-waf"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.afd.id

  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = azurerm_cdn_frontdoor_firewall_policy.waf.id

      association {
        patterns_to_match = ["/*"]

        domain {
          cdn_frontdoor_domain_id = azurerm_cdn_frontdoor_custom_domain.dominio.id
        }

        domain {
          cdn_frontdoor_domain_id = azurerm_cdn_frontdoor_endpoint.ep.id
        }
      }
    }
  }
}

# ---------- Diagnósticos ----------
resource "azurerm_log_analytics_workspace" "law" {
  name                = "law-afd"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_monitor_diagnostic_setting" "afd" {
  name                       = "diag-afd"
  target_resource_id         = azurerm_cdn_frontdoor_profile.afd.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  enabled_log {
    category = "FrontDoorAccessLog"
  }

  enabled_log {
    category = "FrontDoorHealthProbeLog"
  }

  enabled_log {
    category = "FrontDoorWebApplicationFirewallLog"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

output "endpoint_hostname" {
  description = "Apunta tu CNAME aquí"
  value       = azurerm_cdn_frontdoor_endpoint.ep.host_name
}

output "validacion_dominio_txt" {
  description = "Crea un TXT _dnsauth.<subdominio> con este valor"
  value       = azurerm_cdn_frontdoor_custom_domain.dominio.validation_token
}

output "front_door_id" {
  description = "Valor que X-Azure-FDID traerá en cada petición"
  value       = azurerm_cdn_frontdoor_profile.afd.resource_guid
}
