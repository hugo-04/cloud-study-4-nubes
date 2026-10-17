terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
  }
}

variable "cuenta_facturacion" {
  type = string
}

variable "proyecto_finanzas" {
  type = string
}

variable "numero_proyecto_tienda" {
  type = string
}

resource "google_pubsub_topic" "presupuestos" {
  project = var.proyecto_finanzas
  name    = "presupuestos"
}

resource "google_billing_budget" "tienda_prod" {
  billing_account = var.cuenta_facturacion
  display_name    = "tienda-prod"

  budget_filter {
    projects               = ["projects/${var.numero_proyecto_tienda}"]
    credit_types_treatment = "INCLUDE_ALL_CREDITS"
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = "3000"
    }
  }

  threshold_rules {
    threshold_percent = 0.5
  }

  threshold_rules {
    threshold_percent = 0.9
  }

  threshold_rules {
    threshold_percent = 1.0
  }

  threshold_rules {
    threshold_percent = 1.1
    spend_basis       = "FORECASTED_SPEND"
  }

  all_updates_rule {
    pubsub_topic                    = google_pubsub_topic.presupuestos.id
    schema_version                  = "1.0"
    disable_default_iam_recipients  = false
    enable_project_level_recipients = true
  }
}
