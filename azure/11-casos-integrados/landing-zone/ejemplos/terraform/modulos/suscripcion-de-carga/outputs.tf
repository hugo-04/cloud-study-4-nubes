output "grupo_de_recursos_carga" {
  value = azurerm_resource_group.carga.name
}

output "red_id" {
  value = azurerm_virtual_network.spoke.id
}

output "subred_aplicacion_id" {
  value = azurerm_subnet.aplicacion.id
}

output "subred_privada_id" {
  value = azurerm_subnet.datos.id
}
