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

variable "compartimento_prod_id" {
  type        = string
  description = "Compartimento padre de producción (la regla ve sus hijos)"
}

variable "tema_seguridad_id" {
  type = string
}

variable "funcion_limpieza_id" {
  type = string
}

resource "oci_events_rule" "cambios_iam_red" {
  compartment_id = var.compartimento_prod_id
  display_name   = "seguridad-cambios-iam-y-red"
  description    = "Políticas IAM, listas de seguridad y NSG"
  is_enabled     = true
  condition = jsonencode({
    eventType = [
      "com.oraclecloud.identitycontrolplane.createpolicy",
      "com.oraclecloud.identitycontrolplane.updatepolicy",
      "com.oraclecloud.identitycontrolplane.deletepolicy",
      "com.oraclecloud.virtualnetwork.updatesecuritylist",
      "com.oraclecloud.virtualnetwork.updatenetworksecuritygroupsecurityrules",
    ]
  })

  actions {
    actions {
      action_type = "ONS"
      is_enabled  = true
      topic_id    = var.tema_seguridad_id
    }
  }
}

resource "oci_events_rule" "instancia_terminada" {
  compartment_id = var.compartimento_prod_id
  display_name   = "limpieza-dns-al-terminar"
  is_enabled     = true
  condition = jsonencode({
    eventType = ["com.oraclecloud.computeapi.terminateinstance.end"]
  })

  actions {
    actions {
      action_type = "FAAS"
      is_enabled  = true
      function_id = var.funcion_limpieza_id
    }
  }
}
