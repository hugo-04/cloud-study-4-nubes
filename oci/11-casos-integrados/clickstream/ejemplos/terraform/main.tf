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

variable "subred_privada_id" {
  type = string
}

variable "namespace" {
  type = string
}

resource "oci_streaming_stream_pool" "analitica" {
  compartment_id = var.compartimento_id
  name           = "analitica"

  private_endpoint_settings {
    subnet_id = var.subred_privada_id
  }
}

resource "oci_streaming_stream" "clickstream" {
  name               = "clickstream"
  stream_pool_id     = oci_streaming_stream_pool.analitica.id
  partitions         = 8
  retention_in_hours = 72
}

resource "oci_objectstorage_bucket" "historial" {
  compartment_id = var.compartimento_id
  namespace      = var.namespace
  name           = "clickstream-historial"
  access_type    = "NoPublicAccess"
  storage_tier   = "Standard"
  auto_tiering   = "InfrequentAccess"
}

resource "oci_sch_service_connector" "historial" {
  compartment_id = var.compartimento_id
  display_name   = "clickstream-a-object-storage"

  source {
    kind      = "streaming"
    stream_id = oci_streaming_stream.clickstream.id
    cursor {
      kind = "TRIM_HORIZON"
    }
  }

  target {
    kind                       = "objectStorage"
    bucket                     = oci_objectstorage_bucket.historial.name
    namespace                  = var.namespace
    object_name_prefix         = "clicks"
    batch_rollover_size_in_mbs = 50
    batch_rollover_time_in_ms  = 300000
  }
}

resource "oci_identity_policy" "conector" {
  compartment_id = var.compartimento_id
  name           = "sch-clickstream"
  description    = "El conector lee el stream y escribe el historial"
  statements = [
    "Allow any-user to use stream-pull in compartment id ${var.compartimento_id} where all {request.principal.type = 'serviceconnector', target.stream.id = '${oci_streaming_stream.clickstream.id}'}",
    "Allow any-user to manage objects in compartment id ${var.compartimento_id} where all {request.principal.type = 'serviceconnector', target.bucket.name = 'clickstream-historial'}",
  ]
}
