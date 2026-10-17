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
  region = var.region_home
}

variable "region_home" {
  type    = string
  default = "us-ashburn-1"
}

variable "compartimento_id" {
  type = string
}

variable "admin_email" {
  type        = string
  description = "Correo del administrador del dominio"
}

# Un dominio aparte para socios externos
resource "oci_identity_domain" "socios" {
  compartment_id = var.compartimento_id
  display_name   = "Socios"
  description    = "Identidades de socios externos"
  home_region    = var.region_home
  license_type   = "free"

  admin_email      = var.admin_email
  admin_first_name = "Admin"
  admin_last_name  = "Socios"
  admin_user_name  = var.admin_email
}

# Grupo dentro del dominio, usando su endpoint propio
resource "oci_identity_domains_group" "logistica" {
  idcs_endpoint = oci_identity_domain.socios.url
  display_name  = "Logistica"
  schemas       = ["urn:ietf:params:scim:schemas:core:2.0:Group"]
}

output "url_dominio" {
  value = oci_identity_domain.socios.url
}
