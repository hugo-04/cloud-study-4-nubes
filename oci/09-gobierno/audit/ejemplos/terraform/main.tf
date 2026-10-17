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

variable "tenancy_id" {
  type = string
}

variable "compartimento_seguridad_id" {
  type = string
}

variable "namespace" {
  type = string
}

resource "oci_audit_configuration" "tenancy" {
  compartment_id        = var.tenancy_id
  retention_period_days = 365
}

resource "oci_objectstorage_bucket" "archivo_audit" {
  compartment_id = var.compartimento_seguridad_id
  namespace      = var.namespace
  name           = "archivo-audit"
  access_type    = "NoPublicAccess"
  storage_tier   = "Standard"

  retention_rules {
    display_name = "siete-anios"
    duration {
      time_amount = 7
      time_unit   = "YEARS"
    }
  }
}

resource "oci_sch_service_connector" "audit_a_bucket" {
  compartment_id = var.compartimento_seguridad_id
  display_name   = "audit-a-object-storage"

  source {
    kind = "logging"
    log_sources {
      compartment_id = var.tenancy_id
      log_group_id   = "_Audit_Include_Subcompartment"
    }
  }

  target {
    kind      = "objectStorage"
    bucket    = oci_objectstorage_bucket.archivo_audit.name
    namespace = var.namespace
  }
}

resource "oci_identity_policy" "conector" {
  compartment_id = var.compartimento_seguridad_id
  name           = "sch-escribe-archivo-audit"
  description    = "El Service Connector escribe en el bucket de archivo"
  statements = [
    "Allow any-user to manage objects in compartment id ${var.compartimento_seguridad_id} where all {request.principal.type = 'serviceconnector', target.bucket.name = 'archivo-audit', request.principal.compartment.id = '${var.compartimento_seguridad_id}'}",
  ]
}
