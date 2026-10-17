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

variable "nsg_lb_id" {
  type        = string
  description = "NSG del LB: 443 desde Internet; salida al NSG de los backends"
}

variable "backends" {
  type        = list(string)
  description = "IPs privadas de las réplicas del catálogo"
  default     = ["10.0.2.11", "10.0.2.12"]
}

variable "certificado_pem" {
  type      = string
  sensitive = true
}

variable "llave_privada_pem" {
  type      = string
  sensitive = true
}

resource "oci_load_balancer_load_balancer" "tienda" {
  compartment_id             = var.compartimento_id
  display_name               = "lb-tienda"
  shape                      = "flexible"
  subnet_ids                 = [var.subred_publica_id]
  network_security_group_ids = [var.nsg_lb_id]
  is_private                 = false

  shape_details {
    minimum_bandwidth_in_mbps = 10
    maximum_bandwidth_in_mbps = 100
  }
}

resource "oci_load_balancer_backend_set" "catalogo" {
  load_balancer_id = oci_load_balancer_load_balancer.tienda.id
  name             = "catalogo"
  policy           = "LEAST_CONNECTIONS"

  health_checker {
    protocol          = "HTTP"
    port              = 8080
    url_path          = "/actuator/health/readiness"
    return_code       = 200
    interval_ms       = 10000
    timeout_in_millis = 3000
    retries           = 3
  }
}

resource "oci_load_balancer_backend" "catalogo" {
  for_each         = toset(var.backends)
  load_balancer_id = oci_load_balancer_load_balancer.tienda.id
  backendset_name  = oci_load_balancer_backend_set.catalogo.name
  ip_address       = each.value
  port             = 8080
  weight           = 1
}

resource "oci_load_balancer_certificate" "tienda" {
  load_balancer_id   = oci_load_balancer_load_balancer.tienda.id
  certificate_name   = "tienda-2026"
  public_certificate = var.certificado_pem
  private_key        = var.llave_privada_pem

  lifecycle {
    create_before_destroy = true
  }
}

resource "oci_load_balancer_rule_set" "a_https" {
  load_balancer_id = oci_load_balancer_load_balancer.tienda.id
  name             = "a_https"

  items {
    action        = "REDIRECT"
    response_code = 301
    conditions {
      attribute_name  = "PATH"
      attribute_value = "/"
      operator        = "PREFIX_MATCH"
    }
    redirect_uri {
      protocol = "HTTPS"
      port     = 443
    }
  }
}

resource "oci_load_balancer_listener" "http" {
  load_balancer_id         = oci_load_balancer_load_balancer.tienda.id
  name                     = "http"
  default_backend_set_name = oci_load_balancer_backend_set.catalogo.name
  port                     = 80
  protocol                 = "HTTP"
  rule_set_names           = [oci_load_balancer_rule_set.a_https.name]
}

resource "oci_load_balancer_listener" "https" {
  load_balancer_id         = oci_load_balancer_load_balancer.tienda.id
  name                     = "https"
  default_backend_set_name = oci_load_balancer_backend_set.catalogo.name
  port                     = 443
  protocol                 = "HTTP"

  ssl_configuration {
    certificate_name        = oci_load_balancer_certificate.tienda.certificate_name
    protocols               = ["TLSv1.2", "TLSv1.3"]
    verify_peer_certificate = false
  }

  connection_configuration {
    idle_timeout_in_seconds = 120
  }
}

output "ip_publica" {
  value = oci_load_balancer_load_balancer.tienda.ip_address_details[0].ip_address
}
