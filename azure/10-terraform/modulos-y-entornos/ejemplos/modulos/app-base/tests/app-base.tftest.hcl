# Pruebas del módulo sin tocar Azure: el proveedor se reemplaza por uno simulado (mock_provider).
# Requiere Terraform >= 1.7 u OpenTofu reciente (probado con OpenTofu 1.10; en 1.8 el simulado de azurerm
# todavía exigía el bloque "features"). Ejecuta: tofu test   (o: terraform test)
mock_provider "azurerm" {
  # El simulado inventa valores al azar; el proveedor valida el formato de los ID, así que damos ID válidos.
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

variables {
  nombre_aplicacion = "pedidos"
  entorno           = "dev"
  sufijo            = "001"
  dueno             = "equipo-pedidos"
  contenedores      = ["facturas", "fotos"]
}

run "nombres_y_seguridad_por_defecto" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.name == "stpedidosdev001"
    error_message = "El nombre de la cuenta no sigue la convención."
  }

  assert {
    condition     = azurerm_storage_account.this.shared_access_key_enabled == false && azurerm_storage_account.this.min_tls_version == "TLS1_2"
    error_message = "La cuenta debe nacer sin claves y con TLS 1.2."
  }

  assert {
    condition     = azurerm_resource_group.this.tags["dueno"] == "equipo-pedidos" && azurerm_resource_group.this.tags["gestionado"] == "terraform"
    error_message = "Faltan las etiquetas obligatorias."
  }

  assert {
    condition     = length(azurerm_storage_container.this) == 2
    error_message = "Debe crear un contenedor por nombre."
  }
}

run "sin_firewall_si_no_se_restringe" {
  command = plan

  variables {
    restringir_red = false
  }

  assert {
    condition     = length(azurerm_storage_account.this.network_rules) == 0
    error_message = "Sin restringir la red no debe haber bloque network_rules."
  }
}

run "rechaza_un_nombre_invalido" {
  command = plan

  variables {
    nombre_aplicacion = "Pedidos-Grande"
  }

  expect_failures = [var.nombre_aplicacion]
}

run "rechaza_un_entorno_desconocido" {
  command = plan

  variables {
    entorno = "pruebas"
  }

  expect_failures = [var.entorno]
}

run "rechaza_un_nombre_de_cuenta_demasiado_largo" {
  command = plan

  variables {
    nombre_aplicacion = "aplicacionlarg"
    entorno           = "prod"
    sufijo            = "123456"
  }

  expect_failures = [azurerm_storage_account.this]
}
