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

variable "llave_id" {
  type        = string
  description = "CMK en Vault (el servicio necesita 'use keys' sobre ella)"
}

data "oci_objectstorage_namespace" "ns" {
  compartment_id = var.compartimento_id
}

resource "oci_objectstorage_bucket" "comprobantes" {
  compartment_id        = var.compartimento_id
  namespace             = data.oci_objectstorage_namespace.ns.namespace
  name                  = "comprobantes"
  access_type           = "NoPublicAccess"
  storage_tier          = "Standard"
  versioning            = "Enabled"
  object_events_enabled = true
  kms_key_id            = var.llave_id

  freeform_tags = {
    proyecto = "modalima"
    datos    = "personales"
  }
}

resource "oci_objectstorage_object_lifecycle_policy" "comprobantes" {
  namespace = data.oci_objectstorage_namespace.ns.namespace
  bucket    = oci_objectstorage_bucket.comprobantes.name

  rules {
    name        = "archivar-a-los-90-dias"
    action      = "ARCHIVE"
    is_enabled  = true
    time_amount = 90
    time_unit   = "DAYS"
    target      = "objects"
    object_name_filter {
      inclusion_prefixes = ["pedidos/"]
    }
  }

  rules {
    name        = "borrar-versiones-viejas"
    action      = "DELETE"
    is_enabled  = true
    time_amount = 30
    time_unit   = "DAYS"
    target      = "previous-object-versions"
  }

  rules {
    name        = "limpiar-multipart-abandonados"
    action      = "ABORT"
    is_enabled  = true
    time_amount = 7
    time_unit   = "DAYS"
    target      = "multipart-uploads"
  }
}

# Política del servicio para usar tu llave
resource "oci_identity_policy" "servicio_os" {
  compartment_id = var.compartimento_id
  name           = "objectstorage-usa-cmk"
  description    = "Object Storage puede cifrar con la CMK"
  statements = [
    "Allow service objectstorage-${var.region} to use keys in compartment id ${var.compartimento_id} where target.key.id = '${var.llave_id}'",
  ]
}

output "namespace" {
  value = data.oci_objectstorage_namespace.ns.namespace
}
