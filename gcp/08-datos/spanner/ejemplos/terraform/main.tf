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

variable "unidades" {
  type    = number
  default = 100
}

resource "google_spanner_instance" "tienda" {
  name             = "modalima-tienda"
  config           = "regional-southamerica-west1"
  display_name     = "Tienda ModaLima"
  processing_units = var.unidades
  edition          = "STANDARD"
}

resource "google_spanner_database" "tienda" {
  instance                 = google_spanner_instance.tienda.name
  name                     = "tienda"
  deletion_protection      = true
  version_retention_period = "3d"
  ddl = [
    "CREATE TABLE Inventario (Sku STRING(40) NOT NULL, Stock INT64 NOT NULL, Actualizado TIMESTAMP OPTIONS (allow_commit_timestamp=true)) PRIMARY KEY (Sku)",
    "CREATE TABLE Pedidos (PedidoId STRING(36) NOT NULL, Cliente STRING(40), Creado TIMESTAMP) PRIMARY KEY (PedidoId)",
    "CREATE TABLE Lineas (PedidoId STRING(36) NOT NULL, Linea INT64 NOT NULL, Sku STRING(40), Cantidad INT64) PRIMARY KEY (PedidoId, Linea), INTERLEAVE IN PARENT Pedidos ON DELETE CASCADE",
    "CREATE INDEX PedidosPorFecha ON Pedidos(Creado)",
  ]
}

resource "google_service_account" "app" {
  account_id   = "app-tienda"
  display_name = "Tienda"
}

resource "google_spanner_database_iam_member" "app" {
  instance = google_spanner_instance.tienda.name
  database = google_spanner_database.tienda.name
  role     = "roles/spanner.databaseUser"
  member   = "serviceAccount:${google_service_account.app.email}"
}
