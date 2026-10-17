# Cada componente declara SOLO su clave; lo demás llega con -backend-config=backend.hcl.
# Convención de la clave:  <entorno>/<componente>.tfstate

terraform {
  required_version = ">= 1.6"

  backend "azurerm" {
    key = "dev/red.tfstate"
  }
}
