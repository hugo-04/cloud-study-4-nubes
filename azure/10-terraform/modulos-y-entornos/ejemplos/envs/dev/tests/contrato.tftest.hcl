# Prueba de contrato: el archivo que genera el portal (Java) debe ser aceptado por el módulo real.
# terraform -chdir=envs/dev test -var-file=../../generado/aplicaciones.tfvars.json
mock_provider "azurerm" {
  mock_resource "azurerm_resource_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-pruebas"
    }
  }

  mock_resource "azurerm_storage_account" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-pruebas/providers/Microsoft.Storage/storageAccounts/stpruebas"
    }
  }
}

run "el_archivo_generado_es_aceptado" {
  command = plan

  assert {
    condition     = length(module.app) >= 1
    error_message = "El archivo debe definir al menos una aplicación."
  }

  assert {
    condition     = alltrue([for k, m in module.app : startswith(m.cuenta_nombre, "st${k}dev")])
    error_message = "Los nombres de cuenta no siguen la convención."
  }
}
