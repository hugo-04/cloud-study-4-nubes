# Entra ID con Terraform (proveedor azuread): grupo, API con app role, cliente y asignacion del rol.
# terraform init && terraform plan   (terraform destroy al terminar)

terraform {
  required_version = ">= 1.6"

  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azuread" {
  # Autenticacion: `az login` (con permisos en el tenant) o variables ARM_* / OIDC en pipelines.
}

data "azuread_client_config" "actual" {}

resource "random_uuid" "rol_catalogo_read" {}

resource "azuread_group" "desarrollo" {
  display_name     = "sg-desarrollo"
  security_enabled = true
  owners           = [data.azuread_client_config.actual.object_id]
}

# API protegida
resource "azuread_application" "api_catalogo" {
  display_name     = "api-catalogo"
  sign_in_audience = "AzureADMyOrg"
  owners           = [data.azuread_client_config.actual.object_id]

  app_role {
    allowed_member_types = ["Application"]
    description          = "Leer el catalogo"
    display_name         = "Catalogo.Read"
    enabled              = true
    id                   = random_uuid.rol_catalogo_read.result
    value                = "Catalogo.Read"
  }
}

resource "azuread_application_identifier_uri" "api_catalogo" {
  application_id = azuread_application.api_catalogo.id
  identifier_uri = "api://${azuread_application.api_catalogo.client_id}"
}

resource "azuread_service_principal" "api_catalogo" {
  client_id = azuread_application.api_catalogo.client_id
  owners    = [data.azuread_client_config.actual.object_id]
}

# Cliente (otro microservicio)
resource "azuread_application" "svc_inventario" {
  display_name     = "svc-inventario"
  sign_in_audience = "AzureADMyOrg"
  owners           = [data.azuread_client_config.actual.object_id]
}

resource "azuread_service_principal" "svc_inventario" {
  client_id = azuread_application.svc_inventario.client_id
  owners    = [data.azuread_client_config.actual.object_id]
}

# El cliente recibe el app role de la API (equivale al consentimiento de administrador)
resource "azuread_app_role_assignment" "inventario_lee_catalogo" {
  app_role_id         = random_uuid.rol_catalogo_read.result
  principal_object_id = azuread_service_principal.svc_inventario.object_id
  resource_object_id  = azuread_service_principal.api_catalogo.object_id
}

output "audiencia_api" {
  value = "api://${azuread_application.api_catalogo.client_id}"
}
