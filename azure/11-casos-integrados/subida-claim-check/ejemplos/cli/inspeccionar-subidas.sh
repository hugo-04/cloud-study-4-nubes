#!/usr/bin/env bash
# Revisa el estado del flujo de subidas de un entorno. Solo lectura. Requiere: az login y rol de lector de datos.
set -euo pipefail

ENTORNO="${1:?uso: $0 <dev|prod>}"
CUENTA="stsubidas${ENTORNO}001"

echo "== Blobs en cuarentena con más de 1 hora (deberían ser casi cero) =="
az storage blob list --account-name "$CUENTA" --container-name cuarentena --auth-mode login \
  --query "[?properties.lastModified < '$(date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%SZ)'].{nombre:name, tamano:properties.contentLength, modificado:properties.lastModified}" \
  -o table

echo "== Mensajes en la cola de eventos (aproximado) =="
az storage queue stats --account-name "$CUENTA" --name eventos-cuarentena --auth-mode login 2>/dev/null \
  || az storage message peek --account-name "$CUENTA" --queue-name eventos-cuarentena --num-messages 5 --auth-mode login -o table

echo "== Política de limpieza =="
az storage account management-policy show --account-name "$CUENTA" --resource-group "rg-subidas-${ENTORNO}" \
  --query "policy.rules[].{regla:name, activa:enabled}" -o table

echo "== Suscripción de eventos =="
az eventgrid system-topic event-subscription list --system-topic-name "evgt-subidas-${ENTORNO}" \
  --resource-group "rg-subidas-${ENTORNO}" --query "[].{nombre:name, estado:provisioningState}" -o table
