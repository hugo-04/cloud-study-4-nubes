terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
  }
}

variable "organizacion" {
  type        = string
  description = "ID numérico de la organización"
}

variable "cuenta_facturacion" {
  type = string
}

locals {
  labels_obligatorios = ["equipo", "entorno", "centro-costo"]
  proyecto_labels = {
    equipo         = "tienda"
    entorno        = "prod"
    "centro-costo" = "cc-101"
  }
}

resource "google_folder" "produccion" {
  display_name        = "produccion"
  parent              = "organizations/${var.organizacion}"
  deletion_protection = true
}

resource "google_tags_tag_key" "entorno" {
  parent      = "organizations/${var.organizacion}"
  short_name  = "entorno"
  description = "Entorno del recurso (se usa en IAM y políticas)"
}

resource "google_tags_tag_value" "prod" {
  parent     = google_tags_tag_key.entorno.id
  short_name = "prod"
}

resource "google_tags_tag_binding" "carpeta_prod" {
  parent    = "//cloudresourcemanager.googleapis.com/${google_folder.produccion.name}"
  tag_value = google_tags_tag_value.prod.id
}

resource "google_project" "tienda" {
  name            = "modalima-tienda-prod"
  project_id      = "modalima-tienda-prod"
  folder_id       = google_folder.produccion.folder_id
  billing_account = var.cuenta_facturacion
  deletion_policy = "PREVENT"
  labels          = local.proyecto_labels

  lifecycle {
    precondition {
      condition     = alltrue([for k in local.labels_obligatorios : contains(keys(local.proyecto_labels), k)])
      error_message = "Faltan labels obligatorios: equipo, entorno, centro-costo."
    }
  }
}

resource "google_resource_manager_lien" "tienda" {
  parent       = "projects/${google_project.tienda.number}"
  restrictions = ["resourcemanager.projects.delete"]
  origin       = "plataforma-modalima"
  reason       = "Proyecto de producción"
}
