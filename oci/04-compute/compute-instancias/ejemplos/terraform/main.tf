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
  region = var.region
}

variable "region" {
  type    = string
  default = "sa-saopaulo-1"
}

variable "compartimento_id" {
  type = string
}

variable "dominio_disponibilidad" {
  type = string
}

variable "subred_id" {
  type        = string
  description = "Subred PRIVADA"
}

variable "nsg_id" {
  type = string
}

variable "imagen_id" {
  type        = string
  description = "OCID de la imagen (Oracle Linux, ubicada por región)"
}

variable "llave_ssh_publica" {
  type = string
}

resource "oci_core_instance" "app" {
  compartment_id      = var.compartimento_id
  availability_domain = var.dominio_disponibilidad
  display_name        = "app-tienda-dev-01"
  shape               = "VM.Standard.E5.Flex"

  shape_config {
    ocpus         = 2
    memory_in_gbs = 16
  }

  source_details {
    source_type             = "image"
    source_id               = var.imagen_id
    boot_volume_size_in_gbs = 50
  }

  create_vnic_details {
    subnet_id        = var.subred_id
    assign_public_ip = false
    nsg_ids          = [var.nsg_id]
  }

  instance_options {
    are_legacy_imds_endpoints_disabled = true
  }

  metadata = {
    ssh_authorized_keys = var.llave_ssh_publica
    user_data           = base64encode("#cloud-config\npackage_update: true\n")
  }

  freeform_tags = {
    horario     = "lv-08-19"
    entorno     = "dev"
    responsable = "equipo-tienda"
  }
}

output "ip_privada" {
  value = oci_core_instance.app.private_ip
}
