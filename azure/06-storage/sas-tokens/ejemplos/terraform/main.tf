# Lo mínimo para operar SAS de delegación con seguridad:
#  - cuenta SIN clave compartida (solo SAS de delegación y Entra ID)
#  - CORS para subir desde el navegador con la SAS (PUT de bloques con cabeceras x-ms-*)
#  - roles de la identidad que emite SAS: Storage Blob Delegator (cuenta) + Data Contributor (contenedor)
#  - regla de ciclo de vida que limpia subidas no procesadas
# terraform init && terraform plan   (terraform destroy al terminar)

terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}
  storage_use_azuread = true
}

variable "ubicacion" {
  type    = string
  default = "eastus2"
}

variable "origenes_web" {
  type    = list(string)
  default = ["https://tienda.modalima.example"]
}

variable "principal_backend" {
  description = "Object id de la identidad del backend que emite las SAS"
  type        = string
  default     = "00000000-0000-0000-0000-000000000001"
}

resource "random_string" "sufijo" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-estudio-sas"
  location = var.ubicacion
}

resource "azurerm_storage_account" "st" {
  name                            = "stsas${random_string.sufijo.result}"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  account_tier                    = "Standard"
  account_replication_type        = "ZRS"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false # solo SAS de delegación de usuario

  blob_properties {
    cors_rule {
      allowed_origins    = var.origenes_web
      allowed_methods    = ["GET", "PUT", "HEAD", "OPTIONS"]
      allowed_headers    = ["x-ms-*", "content-type", "content-length"]
      exposed_headers    = ["ETag", "x-ms-request-id", "x-ms-version"]
      max_age_in_seconds = 3600
    }

    delete_retention_policy {
      days = 7
    }
  }
}

resource "azurerm_storage_container" "subidas" {
  name                  = "subidas"
  storage_account_id    = azurerm_storage_account.st.id
  container_access_type = "private"
}

# Quien emite la SAS necesita DOS cosas
resource "azurerm_role_assignment" "delegator" {
  scope                = azurerm_storage_account.st.id # a nivel de cuenta
  role_definition_name = "Storage Blob Delegator"
  principal_id         = var.principal_backend
}

resource "azurerm_role_assignment" "datos" {
  scope                = "${azurerm_storage_account.st.id}/blobServices/default/containers/${azurerm_storage_container.subidas.name}"
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.principal_backend
}

# Subidas sin confirmar/analizar en 2 días: fuera
resource "azurerm_storage_management_policy" "limpieza" {
  storage_account_id = azurerm_storage_account.st.id

  rule {
    name    = "borrar-subidas-abandonadas"
    enabled = true

    filters {
      prefix_match = ["subidas/usuarios/"]
      blob_types   = ["blockBlob"]

      match_blob_index_tag {
        name      = "estado"
        operation = "=="
        value     = "sin-confirmar"
      }
    }

    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = 2
      }
    }
  }
}

output "cuenta" {
  value = azurerm_storage_account.st.name
}
