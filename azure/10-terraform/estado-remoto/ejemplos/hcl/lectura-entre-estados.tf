# Leer salidas de OTRO estado (por ejemplo, la red) desde un componente de aplicación.
# Ojo: quien lea el estado ajeno ve TODOS sus valores (incluidos los sensibles).
# Alternativa más segura: leer el recurso con un "data source" de azurerm.

data "terraform_remote_state" "red" {
  backend = "azurerm"

  config = {
    resource_group_name  = "rg-tfstate-modalima"
    storage_account_name = "stmodalimatfstate001"
    container_name       = "tfstate"
    key                  = "dev/red.tfstate"
    use_azuread_auth     = true
  }
}

output "subred_de_aplicacion" {
  value = data.terraform_remote_state.red.outputs.subred_app_id
}
