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

variable "funcion_validador_id" {
  type = string
}

resource "oci_objectstorage_bucket" "subidas" {
  compartment_id        = var.compartimento_id
  namespace             = var.namespace
  name                  = "subidas"
  access_type           = "NoPublicAccess"
  object_events_enabled = true
}

resource "oci_objectstorage_object_lifecycle_policy" "subidas" {
  namespace = var.namespace
  bucket    = oci_objectstorage_bucket.subidas.name

  rules {
    name        = "limpiar-cuarentena"
    action      = "DELETE"
    is_enabled  = true
    time_amount = 1
    time_unit   = "DAYS"
    target      = "objects"
    object_name_filter {
      inclusion_prefixes = ["cuarentena/"]
    }
  }

  rules {
    name        = "abortar-multipart"
    action      = "ABORT"
    is_enabled  = true
    time_amount = 1
    time_unit   = "DAYS"
    target      = "multipart-uploads"
  }
}

resource "oci_events_rule" "llego_a_cuarentena" {
  compartment_id = var.compartimento_id
  display_name   = "subida-a-validador"
  is_enabled     = true
  condition = jsonencode({
    eventType = ["com.oraclecloud.objectstorage.createobject"]
    data      = { additionalDetails = { bucketName = [oci_objectstorage_bucket.subidas.name] } }
  })

  actions {
    actions {
      action_type = "FAAS"
      is_enabled  = true
      function_id = var.funcion_validador_id
    }
  }
}

resource "oci_queue_queue" "procesar" {
  compartment_id                   = var.compartimento_id
  display_name                     = "procesar-imagenes"
  visibility_in_seconds            = 300
  dead_letter_queue_delivery_count = 5
}

resource "oci_identity_policy" "validador" {
  compartment_id = var.compartimento_id
  name           = "validador-subidas"
  description    = "La función valida, mueve y encola"
  statements = [
    "Allow service cloudEvents to use fn-invocation in compartment id ${var.compartimento_id}",
    "Allow dynamic-group funciones-tienda to manage objects in compartment id ${var.compartimento_id} where target.bucket.name = 'subidas'",
    "Allow dynamic-group funciones-tienda to use queues in compartment id ${var.compartimento_id} where target.queue.id = '${oci_queue_queue.procesar.id}'",
  ]
}
