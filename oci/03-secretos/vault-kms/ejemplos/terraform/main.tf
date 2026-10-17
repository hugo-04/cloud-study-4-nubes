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

variable "compartimento_nombre" {
  type    = string
  default = "tienda-prod"
}

resource "oci_kms_vault" "tienda" {
  compartment_id = var.compartimento_id
  display_name   = "vault-tienda-prod"
  vault_type     = "DEFAULT"
}

resource "oci_kms_key" "datos" {
  compartment_id      = var.compartimento_id
  display_name        = "llave-datos-tienda"
  management_endpoint = oci_kms_vault.tienda.management_endpoint
  protection_mode     = "HSM"

  key_shape {
    algorithm = "AES"
    length    = 32
  }
}

# La aplicación solo puede usar ESTA llave
resource "oci_identity_policy" "uso_de_llave" {
  compartment_id = var.compartimento_id
  name           = "app-tienda-usa-llave"
  description    = "Cifrar y descifrar con una llave concreta"
  statements = [
    "Allow dynamic-group app-tienda-prod to use keys in compartment ${var.compartimento_nombre} where target.key.id = '${oci_kms_key.datos.id}'",
  ]
}

output "endpoint_criptografia" {
  value = oci_kms_vault.tienda.crypto_endpoint
}

output "llave_id" {
  value = oci_kms_key.datos.id
}
