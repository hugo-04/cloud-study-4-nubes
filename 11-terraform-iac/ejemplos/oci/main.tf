# Laboratorio OCI: VCN privada + Service Gateway + bucket sin acceso publico.
# Material de estudio. Ejecuta: terraform init && terraform plan
# Requiere un compartimento existente (su OCID) y credenciales en ~/.oci/config.
# Al terminar: terraform destroy

terraform {
  required_version = ">= 1.6"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 6.0"
    }
  }
}

variable "region" {
  type    = string
  default = "us-ashburn-1"
}

variable "compartment_ocid" {
  type        = string
  description = "OCID del compartimento donde se crean los recursos"
}

provider "oci" {
  region = var.region
  # Autenticacion: perfil DEFAULT de ~/.oci/config o variables de entorno del provider.
}

data "oci_objectstorage_namespace" "ns" {
  compartment_id = var.compartment_ocid
}

# Servicios de Oracle accesibles por el Service Gateway (Object Storage, etc.).
data "oci_core_services" "todos" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = ["10.30.0.0/16"]
  display_name   = "vcn-estudio"
  dns_label      = "estudio"
}

resource "oci_core_service_gateway" "sgw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "sgw-estudio"

  services {
    service_id = data.oci_core_services.todos.services[0].id
  }
}

# Ruta privada: el trafico hacia servicios de Oracle sale por el Service Gateway, no por internet.
resource "oci_core_route_table" "privada" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "rt-privada"

  route_rules {
    destination       = data.oci_core_services.todos.services[0].cidr_block
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.sgw.id
  }
}

resource "oci_core_subnet" "app" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = "10.30.1.0/24"
  display_name               = "snet-app"
  route_table_id             = oci_core_route_table.privada.id
  prohibit_public_ip_on_vnic = true
}

resource "oci_core_network_security_group" "app" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "nsg-app"
}

resource "oci_core_network_security_group_security_rule" "https_desde_web" {
  network_security_group_id = oci_core_network_security_group.app.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = "10.30.0.0/24"
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 443
      max = 443
    }
  }
}

resource "oci_objectstorage_bucket" "datos" {
  compartment_id = var.compartment_ocid
  namespace      = data.oci_objectstorage_namespace.ns.namespace
  name           = "modalima-estudio-datos"
  access_type    = "NoPublicAccess"
  versioning     = "Enabled"
}

output "nombre_bucket" {
  value = oci_objectstorage_bucket.datos.name
}

output "subnet_app_id" {
  value = oci_core_subnet.app.id
}
