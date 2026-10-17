#!/usr/bin/env bash
# Operaciones habituales con el estado remoto de Terraform en Azure.
# Ajusta estas variables; ninguna es secreta.
set -euo pipefail

CUENTA="${CUENTA:-stmodalimatfstate001}"
CONTENEDOR="${CONTENEDOR:-tfstate}"
GRUPO="${GRUPO:-rg-tfstate-modalima}"

# ---------------------------------------------------------------------------------------------
# 1) ARRANQUE (una sola vez): crear el almacén con estado local y luego migrarlo a sí mismo
# ---------------------------------------------------------------------------------------------
arranque() {
  az login                                   # tu usuario necesita Owner (o Contributor + UAA) en la suscripción de plataforma
  cd terraform
  terraform init
  terraform apply -var "subscription_id=$(az account show --query id -o tsv)" \
                  -var 'ips_permitidas=["<TU_IP_PUBLICA>"]'
  terraform output -json configuracion_del_backend

  # Añade ../hcl/backend.tf (con key = "plataforma/estado.tfstate") y backend.hcl en esta carpeta, y migra:
  terraform init -migrate-state -backend-config=backend.hcl
  # Comprueba que el estado local ya no se usa:
  rm -f terraform.tfstate terraform.tfstate.backup
}

# ---------------------------------------------------------------------------------------------
# 2) INVENTARIO de estados: tamaño, último cambio y si alguien lo tiene bloqueado (lease)
# ---------------------------------------------------------------------------------------------
inventario() {
  az storage blob list --account-name "$CUENTA" --container-name "$CONTENEDOR" --auth-mode login \
    --query "[].{clave:name, bytes:properties.contentLength, modificado:properties.lastModified, lease:properties.lease.state, bloqueo:properties.lease.status}" \
    -o table
}

# ---------------------------------------------------------------------------------------------
# 3) BLOQUEO HUÉRFANO ("Error acquiring the state lock")
# ---------------------------------------------------------------------------------------------
# a) Primero confirma que NADIE está aplicando (pipeline en curso, compañero con la consola abierta).
# b) El mensaje de error muestra un "ID" del bloqueo: se libera con Terraform:
#       terraform force-unlock <ID>
# c) Si Terraform no puede, se rompe el lease del blob (último recurso):
romper_lease() {
  local clave="$1"
  az storage blob lease break --account-name "$CUENTA" --container-name "$CONTENEDOR" \
    --blob-name "$clave" --auth-mode login
}

# ---------------------------------------------------------------------------------------------
# 4) VERSIONES del estado (versionado activado): ver y recuperar una anterior
# ---------------------------------------------------------------------------------------------
versiones() {
  local clave="$1"
  az storage blob list --account-name "$CUENTA" --container-name "$CONTENEDOR" --auth-mode login \
    --include v --prefix "$clave" \
    --query "[].{version:versionId, actual:isCurrentVersion, modificado:properties.lastModified, bytes:properties.contentLength}" -o table
}

recuperar_version() {
  local clave="$1" version="$2"
  az storage blob download --account-name "$CUENTA" --container-name "$CONTENEDOR" --name "$clave" \
    --version-id "$version" --file "recuperado.tfstate" --auth-mode login
  # Revisa el archivo (serial, recursos) ANTES de subirlo; subirlo crea una versión nueva y deja la historia intacta:
  az storage blob upload --account-name "$CUENTA" --container-name "$CONTENEDOR" --name "$clave" \
    --file "recuperado.tfstate" --overwrite --auth-mode login
}

# ---------------------------------------------------------------------------------------------
# 5) Cirugía del estado (siempre con una copia a mano y un plan después)
# ---------------------------------------------------------------------------------------------
cirugia() {
  terraform state list
  terraform state show 'azurerm_storage_account.estado'
  terraform state mv  'azurerm_virtual_network.vnet' 'module.red.azurerm_virtual_network.vnet'   # preferible: bloque "moved" en el código
  terraform state rm  'azurerm_storage_account.antigua'                                          # deja de administrarla, NO la borra en Azure
  terraform plan -refresh-only                                                                    # ver la diferencia con la realidad sin cambiar nada
}

# ---------------------------------------------------------------------------------------------
# 6) CAMBIAR DE BACKEND
# ---------------------------------------------------------------------------------------------
#   terraform init -migrate-state -backend-config=backend.hcl   # copia el estado al backend nuevo
#   terraform init -reconfigure   -backend-config=backend.hcl    # solo apunta al nuevo, SIN copiar

"${@:-inventario}"
