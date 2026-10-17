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

variable "vault_id" {
  type = string
}

variable "llave_id" {
  type = string
}

variable "valor_inicial" {
  type        = string
  sensitive   = true
  description = "Valor provisional: se cambia fuera de Terraform tras crear"
}

resource "oci_vault_secret" "pedidos_db" {
  compartment_id = var.compartimento_id
  vault_id       = var.vault_id
  key_id         = var.llave_id
  secret_name    = "pedidos-db-password"
  description    = "Contraseña de la base de pedidos"

  secret_content {
    content_type = "BASE64"
    content      = base64encode(var.valor_inicial)
  }

  secret_rules {
    rule_type                              = "SECRET_EXPIRY_RULE"
    secret_version_expiry_interval         = "P90D"
    is_enforced_on_deleted_secret_versions = false
  }

  lifecycle {
    ignore_changes = [secret_content]
  }
}

resource "oci_identity_policy" "lee_secreto" {
  compartment_id = var.compartimento_id
  name           = "app-pedidos-lee-secreto"
  description    = "La aplicación lee solo este secreto"
  statements = [
    "Allow dynamic-group app-pedidos-prod to read secret-bundles in compartment ${var.compartimento_nombre} where target.secret.id = '${oci_vault_secret.pedidos_db.id}'",
  ]
}
