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

variable "namespace" {
  type = string
}

variable "funcion_id" {
  type        = string
  description = "Función que genera miniaturas"
}

resource "oci_objectstorage_bucket" "fotos" {
  compartment_id        = var.compartimento_id
  namespace             = var.namespace
  name                  = "fotos-productos"
  access_type           = "NoPublicAccess"
  object_events_enabled = true
}

# Destino distinto para evitar ciclos de eventos
resource "oci_objectstorage_bucket" "miniaturas" {
  compartment_id = var.compartimento_id
  namespace      = var.namespace
  name           = "miniaturas"
  access_type    = "NoPublicAccess"
}

resource "oci_events_rule" "foto_subida" {
  compartment_id = var.compartimento_id
  display_name   = "foto-subida-a-miniaturas"
  is_enabled     = true
  condition = jsonencode({
    eventType = ["com.oraclecloud.objectstorage.createobject", "com.oraclecloud.objectstorage.updateobject"]
    data = {
      additionalDetails = {
        bucketName = [oci_objectstorage_bucket.fotos.name]
      }
    }
  })

  actions {
    actions {
      action_type = "FAAS"
      is_enabled  = true
      function_id = var.funcion_id
      description = "Genera miniaturas"
    }
  }
}

# Events puede invocar funciones del compartimento
resource "oci_identity_policy" "events_fn" {
  compartment_id = var.compartimento_id
  name           = "events-invoca-funciones"
  description    = "Reglas de Events invocan funciones"
  statements = [
    "Allow service cloudEvents to use fn-invocation in compartment id ${var.compartimento_id}",
  ]
}
