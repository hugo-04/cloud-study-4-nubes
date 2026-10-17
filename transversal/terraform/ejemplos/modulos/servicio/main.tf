# Módulo genérico: genera el «manifiesto» de un servicio (nombre, sufijo único, colas) en un archivo local.
terraform {
  required_version = ">= 1.6"
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

variable "nombre" {
  type = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,24}$", var.nombre))
    error_message = "nombre: minúsculas, números y guiones (3-25)."
  }
}

variable "entorno" {
  type = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.entorno)
    error_message = "entorno: dev, staging o prod."
  }
}

variable "colas" {
  type    = set(string)
  default = []
}

variable "replicas" {
  type    = number
  default = 1
}

locals {
  nombre_completo = "${var.nombre}-${var.entorno}"
}

resource "random_id" "sufijo" {
  byte_length = 3
  keepers = {
    nombre = local.nombre_completo
  }
}

resource "local_file" "manifiesto" {
  filename = "${path.root}/salida/${local.nombre_completo}.json"
  content = jsonencode({
    servicio = local.nombre_completo
    id       = "${local.nombre_completo}-${random_id.sufijo.hex}"
    replicas = var.replicas
    colas    = { for c in var.colas : c => "${local.nombre_completo}-${c}" }
  })

  lifecycle {
    precondition {
      condition     = var.entorno != "prod" || var.replicas >= 2
      error_message = "En prod se requieren al menos 2 réplicas."
    }
  }
}

output "id" {
  value = "${local.nombre_completo}-${random_id.sufijo.hex}"
}

output "colas" {
  value = sort([for c in var.colas : "${local.nombre_completo}-${c}"])
}

output "replicas" {
  value = var.replicas
}
