terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
  }
}

provider "google" {
  project = var.proyecto
}

variable "proyecto" {
  type = string
}

resource "google_storage_bucket" "subidas" {
  name                        = "modalima-subidas"
  location                    = "SOUTHAMERICA-WEST1"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  lifecycle_rule {
    condition {
      age            = 1
      matches_prefix = ["cuarentena/"]
    }
    action {
      type = "Delete"
    }
  }
}

resource "google_pubsub_topic" "llegadas" {
  name = "subidas-llegadas"
}

resource "google_pubsub_topic" "aprobadas" {
  name = "subidas-aprobadas"
}

data "google_storage_project_service_account" "gcs" {}

resource "google_pubsub_topic_iam_member" "gcs_publica" {
  topic  = google_pubsub_topic.llegadas.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${data.google_storage_project_service_account.gcs.email_address}"
}

resource "google_storage_notification" "llegadas" {
  bucket             = google_storage_bucket.subidas.name
  topic              = google_pubsub_topic.llegadas.id
  payload_format     = "JSON_API_V1"
  event_types        = ["OBJECT_FINALIZE"]
  object_name_prefix = "cuarentena/"
  depends_on         = [google_pubsub_topic_iam_member.gcs_publica]
}

resource "google_service_account" "subidas" {
  account_id = "run-subidas"
}

resource "google_service_account" "validador" {
  account_id = "run-validador"
}

# signBlob sin llaves: la SA se firma a sí misma
resource "google_service_account_iam_member" "firma" {
  service_account_id = google_service_account.subidas.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_service_account.subidas.email}"
}

# La URL firmada actúa con los permisos de quien firma: solo crear, y solo en cuarentena/
resource "google_storage_bucket_iam_member" "subidas_crea" {
  bucket = google_storage_bucket.subidas.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.subidas.email}"

  condition {
    title      = "solo-cuarentena"
    expression = "resource.name.startsWith('projects/_/buckets/modalima-subidas/objects/cuarentena/')"
  }
}

resource "google_storage_bucket_iam_member" "validador" {
  bucket = google_storage_bucket.subidas.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.validador.email}"
}

resource "google_pubsub_topic_iam_member" "validador_publica" {
  topic  = google_pubsub_topic.aprobadas.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${google_service_account.validador.email}"
}
