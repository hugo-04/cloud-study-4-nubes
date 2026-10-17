terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
  }
}

provider "google" {
  project = var.proyecto
}

variable "proyecto" {
  type = string
}

variable "bloquear_waf" {
  type        = bool
  default     = false
  description = "false = vista previa durante el ajuste"
}

resource "google_compute_security_policy" "tienda" {
  name = "tienda"

  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable = true
    }
  }

  rule {
    action   = "rate_based_ban"
    priority = 200
    match {
      expr {
        expression = "request.path.startsWith('/v1/login')"
      }
    }
    rate_limit_options {
      conform_action   = "allow"
      exceed_action    = "deny(429)"
      enforce_on_key   = "IP"
      ban_duration_sec = 600
      rate_limit_threshold {
        count        = 10
        interval_sec = 60
      }
    }
    description = "fuerza bruta en login"
  }

  rule {
    action   = "deny(403)"
    priority = 1000
    preview  = !var.bloquear_waf
    match {
      expr {
        expression = "evaluatePreconfiguredWaf('sqli-v33-stable', {'sensitivity': 1})"
      }
    }
    description = "inyección SQL"
  }

  rule {
    action   = "deny(403)"
    priority = 1001
    preview  = !var.bloquear_waf
    match {
      expr {
        expression = "evaluatePreconfiguredWaf('xss-v33-stable', {'sensitivity': 1})"
      }
    }
    description = "XSS"
  }

  rule {
    action   = "allow"
    priority = 2147483647
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "por defecto"
  }
}
