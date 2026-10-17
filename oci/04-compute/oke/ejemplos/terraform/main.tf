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

variable "vcn_id" {
  type = string
}

variable "subred_api_id" {
  type = string
}

variable "subred_nodos_id" {
  type = string
}

variable "subred_pods_id" {
  type = string
}

variable "subred_lb_id" {
  type = string
}

variable "dominio_disponibilidad" {
  type = string
}

variable "imagen_nodos_id" {
  type = string
}

variable "version_k8s" {
  type    = string
  default = "v1.31.1"
}

resource "oci_containerengine_cluster" "tienda" {
  compartment_id     = var.compartimento_id
  kubernetes_version = var.version_k8s
  name               = "oke-tienda-prod"
  vcn_id             = var.vcn_id
  type               = "ENHANCED_CLUSTER"

  endpoint_config {
    is_public_ip_enabled = false
    subnet_id            = var.subred_api_id
  }

  cluster_pod_network_options {
    cni_type = "OCI_VCN_IP_NATIVE"
  }

  options {
    service_lb_subnet_ids = [var.subred_lb_id]
  }
}

resource "oci_containerengine_node_pool" "general" {
  cluster_id         = oci_containerengine_cluster.tienda.id
  compartment_id     = var.compartimento_id
  kubernetes_version = var.version_k8s
  name               = "pool-general"
  node_shape         = "VM.Standard.E5.Flex"

  node_shape_config {
    ocpus         = 2
    memory_in_gbs = 16
  }

  node_source_details {
    image_id    = var.imagen_nodos_id
    source_type = "IMAGE"
  }

  node_config_details {
    size = 3

    placement_configs {
      availability_domain = var.dominio_disponibilidad
      subnet_id           = var.subred_nodos_id
    }

    node_pool_pod_network_option_details {
      cni_type          = "OCI_VCN_IP_NATIVE"
      pod_subnet_ids    = [var.subred_pods_id]
      max_pods_per_node = 31
    }
  }
}

output "cluster_id" {
  value = oci_containerengine_cluster.tienda.id
}
