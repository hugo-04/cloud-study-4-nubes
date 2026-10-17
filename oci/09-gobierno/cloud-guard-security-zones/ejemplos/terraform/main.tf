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

variable "compartimento_modalima_id" {
  type = string
}

variable "compartimento_prod_id" {
  type = string
}

variable "receta_detector_config_id" {
  type        = string
  description = "Receta de detector de configuración (clonada de la de Oracle)"
}

variable "receta_responder_id" {
  type = string
}

variable "politicas_zona" {
  type        = list(string)
  description = "OCIDs de políticas de Security Zone (por ejemplo, deny public buckets); listarlas con la CLI"
}

resource "oci_cloud_guard_cloud_guard_configuration" "tenancy" {
  compartment_id   = var.tenancy_id
  reporting_region = var.region
  status           = "ENABLED"
}

resource "oci_cloud_guard_target" "modalima" {
  compartment_id       = var.compartimento_modalima_id
  display_name         = "modalima"
  target_resource_id   = var.compartimento_modalima_id
  target_resource_type = "COMPARTMENT"

  target_detector_recipes {
    detector_recipe_id = var.receta_detector_config_id
  }

  target_responder_recipes {
    responder_recipe_id = var.receta_responder_id
  }

  depends_on = [oci_cloud_guard_cloud_guard_configuration.tenancy]
}

resource "oci_cloud_guard_security_recipe" "prod" {
  compartment_id    = var.compartimento_modalima_id
  display_name      = "receta-prod-segura"
  security_policies = var.politicas_zona
}

resource "oci_cloud_guard_security_zone" "prod" {
  compartment_id          = var.compartimento_prod_id
  display_name            = "zona-prod"
  security_zone_recipe_id = oci_cloud_guard_security_recipe.prod.id
}
