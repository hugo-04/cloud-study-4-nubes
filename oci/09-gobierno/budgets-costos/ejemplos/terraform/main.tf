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

variable "compartimento_prod_id" {
  type = string
}

variable "correos" {
  type    = string
  default = "finanzas@modalima.example,plataforma@modalima.example"
}

resource "oci_budget_budget" "prod" {
  compartment_id = var.tenancy_id
  display_name   = "modalima-prod"
  amount         = 5000
  reset_period   = "MONTHLY"
  target_type    = "COMPARTMENT"
  targets        = [var.compartimento_prod_id]
}

resource "oci_budget_alert_rule" "real_80" {
  budget_id      = oci_budget_budget.prod.id
  display_name   = "real-80"
  type           = "ACTUAL"
  threshold      = 80
  threshold_type = "PERCENTAGE"
  recipients     = var.correos
  message        = "ModaLima prod superó el 80 % del presupuesto mensual"
}

resource "oci_budget_alert_rule" "proyectado_100" {
  budget_id      = oci_budget_budget.prod.id
  display_name   = "proyectado-100"
  type           = "FORECAST"
  threshold      = 100
  threshold_type = "PERCENTAGE"
  recipients     = var.correos
  message        = "Al ritmo actual, ModaLima prod superará el presupuesto este mes"
}

# Presupuesto por etiqueta de costo (producto pagos)
resource "oci_budget_budget" "pagos" {
  compartment_id = var.tenancy_id
  display_name   = "producto-pagos"
  amount         = 1200
  reset_period   = "MONTHLY"
  target_type    = "TAG"
  targets        = ["Gobierno.centro_costo.pagos"]
}
