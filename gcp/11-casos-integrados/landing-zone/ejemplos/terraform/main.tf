terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
  }
}

variable "carpeta_padre" {
  type        = string
  description = "folders/<id> donde cuelgan las unidades"
}

variable "cuenta_facturacion" {
  type = string
}

variable "proyecto_host" {
  type = string
}

variable "cidr_unidad" {
  type        = string
  default     = "10.24.0.0/16"
  description = "Propuesto por el planificador"
}

variable "tag_entorno" {
  type        = map(string)
  description = "entorno => id del TagValue (tagValues/...)"
}

locals {
  unidad = "tostaduria"
  entornos = {
    prod = { cidr = cidrsubnet(var.cidr_unidad, 1, 0), proyecto = "cafeandino-${local.unidad}-prod" }
    dev  = { cidr = cidrsubnet(var.cidr_unidad, 1, 1), proyecto = "cafeandino-${local.unidad}-dev" }
  }
}

resource "google_folder" "unidad" {
  display_name = local.unidad
  parent       = var.carpeta_padre
}

resource "google_folder" "entorno" {
  for_each     = local.entornos
  display_name = each.key
  parent       = google_folder.unidad.name
}

resource "google_tags_tag_binding" "entorno" {
  for_each  = local.entornos
  parent    = "//cloudresourcemanager.googleapis.com/${google_folder.entorno[each.key].name}"
  tag_value = var.tag_entorno[each.key]
}

resource "google_project" "entorno" {
  for_each        = local.entornos
  name            = each.value.proyecto
  project_id      = each.value.proyecto
  folder_id       = google_folder.entorno[each.key].folder_id
  billing_account = var.cuenta_facturacion
  deletion_policy = each.key == "prod" ? "PREVENT" : "DELETE"
  labels = {
    equipo         = local.unidad
    entorno        = each.key
    "centro-costo" = "cc-${local.unidad}"
  }
}

resource "google_compute_shared_vpc_service_project" "entorno" {
  for_each        = local.entornos
  host_project    = var.proyecto_host
  service_project = google_project.entorno[each.key].project_id
}

resource "google_compute_subnetwork" "entorno" {
  for_each      = local.entornos
  project       = var.proyecto_host
  name          = "${local.unidad}-${each.key}"
  region        = "southamerica-west1"
  network       = "projects/${var.proyecto_host}/global/networks/vpc-compartida"
  ip_cidr_range = cidrsubnet(each.value.cidr, 3, 0)

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = cidrsubnet(each.value.cidr, 1, 1)
  }

  secondary_ip_range {
    range_name    = "servicios"
    ip_cidr_range = cidrsubnet(each.value.cidr, 3, 1)
  }

  private_ip_google_access = true
}

resource "google_compute_subnetwork_iam_member" "devs" {
  for_each   = local.entornos
  project    = var.proyecto_host
  region     = "southamerica-west1"
  subnetwork = google_compute_subnetwork.entorno[each.key].name
  role       = "roles/compute.networkUser"
  member     = "group:${local.unidad}-devs@cafeandino.example"
}

resource "google_folder_iam_member" "roles" {
  for_each = {
    "prod-viewer" = { carpeta = "prod", rol = "roles/viewer", grupo = "devs" }
    "dev-editor"  = { carpeta = "dev", rol = "roles/editor", grupo = "devs" }
    "prod-run"    = { carpeta = "prod", rol = "roles/run.admin", grupo = "admins" }
  }
  folder = google_folder.entorno[each.value.carpeta].name
  role   = each.value.rol
  member = "group:${local.unidad}-${each.value.grupo}@cafeandino.example"
}

resource "google_resource_manager_lien" "prod" {
  parent       = "projects/${google_project.entorno["prod"].number}"
  restrictions = ["resourcemanager.projects.delete"]
  origin       = "landing-zone"
  reason       = "Unidad ${local.unidad} en producción"
}
