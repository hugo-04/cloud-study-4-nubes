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

variable "sa_pedidos" {
  type = string
}

variable "tema_rotacion" {
  type        = string
  description = "projects/<p>/topics/rotacion-secretos"
}

resource "google_secret_manager_secret" "db_pedidos" {
  secret_id = "db-pedidos-password"

  replication {
    user_managed {
      replicas {
        location = "southamerica-west1"
      }
      replicas {
        location = "southamerica-east1"
      }
    }
  }

  rotation {
    rotation_period    = "7776000s" # 90 días
    next_rotation_time = "2026-12-01T00:00:00Z"
  }

  topics {
    name = var.tema_rotacion
  }

  labels = {
    centro_costo = "tienda"
  }
}

# Solo la app de pedidos lee ESTE secreto
resource "google_secret_manager_secret_iam_member" "pedidos_lee" {
  secret_id = google_secret_manager_secret.db_pedidos.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.sa_pedidos}"
}
