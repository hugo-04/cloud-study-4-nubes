#!/usr/bin/env bash
# Bloqueos de recursos con Azure CLI (versión de estudio). No ejecutes todo de golpe: es una guía de comandos.
set -euo pipefail

RG="rg-modalima-prod-datos"
DNS="privatelink.database.windows.net"

# ---------------------------------------------------------------------------------------------
# 1) CREAR bloqueos
# ---------------------------------------------------------------------------------------------
# En un grupo de recursos (el caso habitual)
az lock create \
  --name lock-cannotdelete-$RG \
  --lock-type CanNotDelete \
  --resource-group "$RG" \
  --notes "Producción de datos. Para borrar: ticket aprobado por plataforma."

# En un recurso concreto (zona DNS privada)
az lock create \
  --name lock-cannotdelete-dns-sql \
  --lock-type CanNotDelete \
  --resource-group "$RG" \
  --resource-name "$DNS" \
  --resource-type Microsoft.Network/privateDnsZones \
  --notes "Si se borra, los Private Endpoints de SQL dejan de resolver."

# En la suscripción (úsalo con mucho cuidado; ReadOnly aquí congela todo)
# az lock create --name lock-sub --lock-type CanNotDelete

# ---------------------------------------------------------------------------------------------
# 2) LISTAR y MOSTRAR (incluye los heredados)
# ---------------------------------------------------------------------------------------------
az lock list --resource-group "$RG" -o table
az lock list -o table                                  # toda la suscripción
az lock show --name lock-cannotdelete-$RG --resource-group "$RG" -o jsonc

# ---------------------------------------------------------------------------------------------
# 3) COMPROBAR que protege (en un grupo de LABORATORIO, no en producción)
# ---------------------------------------------------------------------------------------------
# az group delete --name rg-laboratorio-bloqueo --yes
#   → ERROR: (ScopeLocked) The scope '/subscriptions/…/resourceGroups/rg-laboratorio-bloqueo'
#            cannot perform delete operation because following scope(s) are locked: …

# ---------------------------------------------------------------------------------------------
# 4) BORRADO CONTROLADO: quitar el bloqueo → borrar → (volver a poner)
# ---------------------------------------------------------------------------------------------
# az lock delete --name lock-cannotdelete-$RG --resource-group "$RG"
# az group delete --name "$RG" --yes
# (Todo esto debe pasar por un ticket aprobado; el borrado del bloqueo dispara la alerta.)

# ---------------------------------------------------------------------------------------------
# 5) ALTERNATIVA POR ENTORNO: Deployment Stack con denySettings (protege lo que gestiona la pila)
# ---------------------------------------------------------------------------------------------
# az stack group create \
#   --name stack-modalima-prod-datos \
#   --resource-group "$RG" \
#   --template-file ./main.bicep \
#   --action-on-unmanage detachAll \
#   --deny-settings-mode denyWriteAndDelete \
#   --deny-settings-excluded-principals <objectId-del-pipeline> \
#   --deny-settings-apply-to-child-scopes
#   (verifica con `az stack group create --help` los modos y las banderas vigentes)

# ---------------------------------------------------------------------------------------------
# 6) AUDITAR: ¿qué grupos de recursos de producción NO tienen bloqueo?  (Resource Graph)
# ---------------------------------------------------------------------------------------------
az graph query -q "
resourcecontainers
| where type == 'microsoft.resources/subscriptions/resourcegroups'
| where tags['env'] =~ 'prod'
| project subscriptionId, resourceGroup = name
" --first 200 -o table
# Los bloqueos como tal no son recursos consultables en Resource Graph: lista con `az lock list`
# o usa el registro de actividad (ver kql/kql-bloqueos.md) y compara ambas listas.

# ---------------------------------------------------------------------------------------------
# 7) REGISTRO DE ACTIVIDAD: quién creó/borró bloqueos en los últimos 7 días
# ---------------------------------------------------------------------------------------------
az monitor activity-log list \
  --offset 7d \
  --namespace Microsoft.Authorization \
  --query "[?contains(operationName.value,'locks')].{cuando:eventTimestamp, quien:caller, operacion:operationName.value, estado:status.value, recurso:resourceId}" \
  -o table
