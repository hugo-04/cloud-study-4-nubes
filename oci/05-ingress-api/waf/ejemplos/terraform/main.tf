terraform {
  required_version = ">= 1.5"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 7.0"
    }
  }
}

provider "oci" {
  region = var.region
}

variable "region" {
  type    = string
  default = "sa-saopaulo-1"
}

variable "compartimento_id" {
  type = string
}

variable "lb_id" {
  type        = string
  description = "Load Balancer (capa 7) que se protege"
}

variable "modo_bloqueo" {
  type        = bool
  default     = false
  description = "false = solo detectar (CHECK) durante la fase de ajuste; true = bloquear"
}

locals {
  accion_proteccion = var.modo_bloqueo ? "bloquear" : "revisar"
}

resource "oci_waf_web_app_firewall_policy" "tienda" {
  compartment_id = var.compartimento_id
  display_name   = "waf-tienda"

  actions {
    name = "permitir"
    type = "ALLOW"
  }

  actions {
    name = "revisar"
    type = "CHECK"
  }

  actions {
    name = "bloquear"
    type = "RETURN_HTTP_RESPONSE"
    code = 403
    body {
      type = "STATIC_TEXT"
      text = "{\"error\":\"solicitud bloqueada\"}"
    }
  }

  actions {
    name = "demasiadas"
    type = "RETURN_HTTP_RESPONSE"
    code = 429
  }

  # Control de acceso: /admin solo desde la red de la oficina
  request_access_control {
    default_action_name = "permitir"
    rules {
      type               = "ACCESS_CONTROL"
      name               = "admin-solo-oficina"
      action_name        = "bloquear"
      condition_language = "JMESPATH"
      condition          = "starts_with(http.request.url.path, '/admin') && !address_in_range(connection.source.address, '203.0.113.0/24')"
    }
  }

  # Límite de tasa del inicio de sesión
  request_rate_limiting {
    rules {
      type               = "REQUEST_RATE_LIMITING"
      name               = "login"
      action_name        = "demasiadas"
      condition_language = "JMESPATH"
      condition          = "http.request.url.path == '/v1/login'"
      configurations {
        period_in_seconds          = 60
        requests_limit             = 10
        action_duration_in_seconds = 300
      }
    }
  }

  # Protecciones OWASP (claves de capacidades colaborativas; verifica las vigentes)
  request_protection {
    rules {
      type                       = "PROTECTION"
      name                       = "owasp-basico"
      action_name                = local.accion_proteccion
      is_body_inspection_enabled = true
      protection_capabilities {
        key     = "9420000"
        version = 2
      }
      protection_capabilities {
        key     = "9410000"
        version = 3
      }
      protection_capabilities {
        key     = "9330000"
        version = 2
      }
    }
  }
}

resource "oci_waf_web_app_firewall" "tienda" {
  compartment_id             = var.compartimento_id
  display_name               = "waf-lb-tienda"
  backend_type               = "LOAD_BALANCER"
  load_balancer_id           = var.lb_id
  web_app_firewall_policy_id = oci_waf_web_app_firewall_policy.tienda.id
}
