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

variable "proyecto_seguridad" {
  type = string
}

resource "google_pubsub_topic" "hallazgos" {
  project = var.proyecto_seguridad
  name    = "scc-hallazgos-criticos"
}

resource "google_scc_v2_organization_notification_config" "criticos" {
  config_id    = "criticos-activos"
  organization = var.organizacion
  location     = "global"
  description  = "Hallazgos críticos y altos activos, sin silenciar"
  pubsub_topic = google_pubsub_topic.hallazgos.id

  streaming_config {
    filter = "state = \"ACTIVE\" AND mute != \"MUTED\" AND (severity = \"CRITICAL\" OR severity = \"HIGH\")"
  }
}

# Mute puntual: un recurso concreto y una categoría, no todo un tipo
resource "google_scc_v2_organization_mute_config" "laboratorio" {
  mute_config_id = "lab-firewall-aceptado"
  organization   = var.organizacion
  location       = "global"
  description    = "Firewall del laboratorio aislado, aceptado hasta revisión trimestral"
  filter         = "category = \"OPEN_FIREWALL\" AND resource.name = \"//compute.googleapis.com/projects/modalima-lab/global/firewalls/lab-demo\""
  type           = "STATIC"
}
