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

variable "nsg_id" {
  type = string
}

resource "oci_streaming_stream_pool" "tienda" {
  compartment_id = var.compartimento_id
  name           = "eventos-tienda"

  private_endpoint_settings {
    subnet_id = var.subred_privada_id
    nsg_ids   = [var.nsg_id]
  }

  kafka_settings {
    auto_create_topics_enable = false
    num_partitions            = 6
    log_retention_hours       = 24
  }
}

resource "oci_streaming_stream" "clickstream" {
  name               = "clickstream"
  stream_pool_id     = oci_streaming_stream_pool.tienda.id
  partitions         = 6
  retention_in_hours = 72
}

output "endpoint_mensajes" {
  value = oci_streaming_stream.clickstream.messages_endpoint
}

output "bootstrap_kafka" {
  value = oci_streaming_stream_pool.tienda.kafka_settings[0].bootstrap_servers
}
