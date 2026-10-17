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
  type = string
}

variable "proyecto_prod" {
  type = string
}

variable "proyecto_seguridad" {
  type = string
}

# Data Access solo para Secret Manager y KMS en producción
resource "google_project_iam_audit_config" "secretos" {
  for_each = toset(["secretmanager.googleapis.com", "cloudkms.googleapis.com"])
  project  = var.proyecto_prod
  service  = each.value

  audit_log_config {
    log_type = "DATA_READ"
  }

  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

resource "google_logging_project_bucket_config" "auditoria" {
  project        = var.proyecto_seguridad
  location       = "global"
  bucket_id      = "auditoria"
  retention_days = 1095
  locked         = true
}

resource "google_logging_organization_sink" "auditoria" {
  name             = "auditoria-a-seguridad"
  org_id           = var.organizacion
  include_children = true
  destination      = "logging.googleapis.com/projects/${var.proyecto_seguridad}/locations/global/buckets/${google_logging_project_bucket_config.auditoria.bucket_id}"
  filter           = "logName:\"cloudaudit.googleapis.com\""
}

resource "google_project_iam_member" "sink_escribe" {
  project = var.proyecto_seguridad
  role    = "roles/logging.bucketWriter"
  member  = google_logging_organization_sink.auditoria.writer_identity
}
