# Estado «semilla»: crea el bucket del estado (este estado se guarda localmente una vez y luego se migra).
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
  type = string
}

data "oci_objectstorage_namespace" "ns" {
  compartment_id = var.compartimento_id
}

resource "oci_objectstorage_bucket" "estado" {
  compartment_id = var.compartimento_id
  namespace      = data.oci_objectstorage_namespace.ns.namespace
  name           = "tfstate-modalima"
  access_type    = "NoPublicAccess"
  versioning     = "Enabled"
  kms_key_id     = var.llave_id

  lifecycle {
    prevent_destroy = true
  }
}

resource "oci_objectstorage_object_lifecycle_policy" "estado" {
  namespace = data.oci_objectstorage_namespace.ns.namespace
  bucket    = oci_objectstorage_bucket.estado.name

  rules {
    name        = "versiones-90-dias"
    action      = "DELETE"
    is_enabled  = true
    time_amount = 90
    time_unit   = "DAYS"
    target      = "previous-object-versions"
  }
}

resource "oci_identity_policy" "pipelines" {
  compartment_id = var.compartimento_id
  name           = "estado-por-entorno"
  description    = "Cada pipeline solo toca su prefijo del estado"
  statements = [
    "Allow dynamic-group runners-prod to manage objects in compartment id ${var.compartimento_id} where all {target.bucket.name = 'tfstate-modalima', target.object.name = /modalima/prod/*/}",
    "Allow dynamic-group runners-noprod to manage objects in compartment id ${var.compartimento_id} where all {target.bucket.name = 'tfstate-modalima', target.object.name = /modalima/no-prod/*/}",
    "Allow dynamic-group runners-prod to read buckets in compartment id ${var.compartimento_id} where target.bucket.name = 'tfstate-modalima'",
    "Allow dynamic-group runners-noprod to read buckets in compartment id ${var.compartimento_id} where target.bucket.name = 'tfstate-modalima'",
  ]
}
