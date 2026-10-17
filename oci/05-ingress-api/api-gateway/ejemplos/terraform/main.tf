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

variable "subred_publica_id" {
  type = string
}

variable "backend_catalogo" {
  type        = string
  description = "URL privada del catálogo (LB interno o servicio de OKE)"
  default     = "http://10.0.2.10:8080"
}

variable "emisor_jwt" {
  type        = string
  description = "Issuer del identity domain"
}

variable "jwks_uri" {
  type = string
}

resource "oci_apigateway_gateway" "tienda" {
  compartment_id = var.compartimento_id
  display_name   = "gw-tienda"
  endpoint_type  = "PUBLIC"
  subnet_id      = var.subred_publica_id
}

resource "oci_apigateway_deployment" "v1" {
  compartment_id = var.compartimento_id
  gateway_id     = oci_apigateway_gateway.tienda.id
  display_name   = "tienda-v1"
  path_prefix    = "/v1"

  specification {
    request_policies {
      authentication {
        type                        = "JWT_AUTHENTICATION"
        token_header                = "Authorization"
        token_auth_scheme           = "Bearer"
        issuers                     = [var.emisor_jwt]
        audiences                   = ["tienda-api"]
        is_anonymous_access_allowed = true
        max_clock_skew_in_seconds   = 30

        public_keys {
          type                        = "REMOTE_JWKS"
          uri                         = var.jwks_uri
          max_cache_duration_in_hours = 1
        }
      }

      rate_limiting {
        rate_in_requests_per_second = 50
        rate_key                    = "CLIENT_IP"
      }

      cors {
        allowed_origins = ["https://www.modalima.example"]
        allowed_methods = ["GET", "POST"]
        allowed_headers = ["Authorization", "Content-Type"]
      }
    }

    # Catálogo: público (anónimo permitido)
    routes {
      path    = "/catalogo/{resto*}"
      methods = ["GET"]

      backend {
        type                       = "HTTP_BACKEND"
        url                        = "${var.backend_catalogo}/catalogo/$${request.path[resto]}"
        connect_timeout_in_seconds = 5
        read_timeout_in_seconds    = 15
      }
    }

    # Pedidos: requiere usuario autenticado con el alcance adecuado
    routes {
      path    = "/pedidos"
      methods = ["POST"]

      backend {
        type = "HTTP_BACKEND"
        url  = "${var.backend_catalogo}/pedidos"
      }

      request_policies {
        authorization {
          type          = "ANY_OF"
          allowed_scope = ["pedidos.escribir"]
        }
      }
    }

    logging_policies {
      execution_log {
        log_level = "WARN"
      }
    }
  }
}

output "url_base" {
  value = "${oci_apigateway_gateway.tienda.hostname}/v1"
}
