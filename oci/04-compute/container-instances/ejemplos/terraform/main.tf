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
  type        = string
  description = "Nombre del AD, por ejemplo 'Uocm:SA-SAOPAULO-1-AD-1'"
}

variable "subred_id" {
  type        = string
  description = "Subred PRIVADA con salida a OCIR (puerta de servicios) y a Vault"
}

variable "imagen" {
  type        = string
  description = "Etiqueta inmutable, nunca latest. Ejemplo: sa-saopaulo-1.ocir.io/NAMESPACE/reporte-ventas:1.4.2"

  validation {
    condition     = !endswith(var.imagen, ":latest") && can(regex(":[^/]+$|@sha256:", var.imagen))
    error_message = "La imagen debe llevar una etiqueta fija o un digest, y no puede ser latest."
  }
}

variable "secreto_db_id" {
  type        = string
  description = "OCID del secreto en Vault (el contenedor lo lee al arrancar)"
}

# Lote nocturno: corre una vez y queda INACTIVE
resource "oci_container_instances_container_instance" "reporte" {
  compartment_id                       = var.compartimento_id
  availability_domain                  = var.dominio_disponibilidad
  display_name                         = "reporte-ventas-nocturno"
  shape                                = "CI.Standard.E4.Flex"
  container_restart_policy             = "NEVER"
  graceful_shutdown_timeout_in_seconds = 60

  shape_config {
    ocpus         = 1
    memory_in_gbs = 4
  }

  vnics {
    subnet_id             = var.subred_id
    is_public_ip_assigned = false
    display_name          = "reporte-vnic"
  }

  containers {
    display_name = "reporte"
    image_url    = var.imagen

    # Solo configuración NO sensible; el secreto se referencia por OCID
    environment_variables = {
      SECRETO_DB_OCID = var.secreto_db_id
      FECHA_CORTE     = "ayer"
    }

    resource_config {
      vcpus_limit         = 1
      memory_limit_in_gbs = 3.5
    }
  }

  freeform_tags = {
    proyecto = "modalima"
    entorno  = "prod"
  }
}

# Identidad de los contenedores (resource principal)
resource "oci_identity_dynamic_group" "contenedores" {
  compartment_id = var.compartimento_id
  name           = "contenedores-reportes"
  description    = "Container instances de reportes"
  matching_rule  = "ALL {resource.type = 'computecontainerinstance', resource.compartment.id = '${var.compartimento_id}'}"
}

resource "oci_identity_policy" "contenedores" {
  compartment_id = var.compartimento_id
  name           = "contenedores-reportes"
  description    = "Lectura del secreto de la base y escritura de reportes"
  statements = [
    "Allow dynamic-group contenedores-reportes to read secret-bundles in compartment id ${var.compartimento_id} where target.secret.id = '${var.secreto_db_id}'",
    "Allow dynamic-group contenedores-reportes to manage objects in compartment id ${var.compartimento_id} where target.bucket.name = 'reportes'",
  ]
}

output "instancia_id" {
  value = oci_container_instances_container_instance.reporte.id
}
