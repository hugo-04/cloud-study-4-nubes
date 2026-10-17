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

variable "compartimento_nombre" {
  type    = string
  default = "tienda-prod"
}

variable "cluster_id" {
  type        = string
  description = "OCID del clúster OKE (tipo enhanced)"
}

variable "namespace_k8s" {
  type    = string
  default = "tienda"
}

variable "service_account" {
  type    = string
  default = "app-tienda"
}

# Política con los cuatro atributos del principal workload
resource "oci_identity_policy" "workload_tienda" {
  compartment_id = var.compartimento_id
  name           = "workload-app-tienda"
  description    = "El pod app-tienda lee un bucket"
  statements = [
    "Allow any-user to read objects in compartment ${var.compartimento_nombre} where all {request.principal.type = 'workload', request.principal.cluster_id = '${var.cluster_id}', request.principal.namespace = '${var.namespace_k8s}', request.principal.service_account = '${var.service_account}', target.bucket.name = 'comprobantes'}",
  ]
}
