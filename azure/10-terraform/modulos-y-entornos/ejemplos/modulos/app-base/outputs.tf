output "grupo_de_recursos" {
  description = "Nombre del grupo de recursos."
  value       = azurerm_resource_group.this.name
}

output "cuenta_id" {
  description = "ID de la cuenta de almacenamiento."
  value       = azurerm_storage_account.this.id
}

output "cuenta_nombre" {
  description = "Nombre de la cuenta de almacenamiento."
  value       = azurerm_storage_account.this.name
}

output "contenedores" {
  description = "Mapa nombre => ID de los contenedores."
  value       = { for k, c in azurerm_storage_container.this : k => c.id }
}
