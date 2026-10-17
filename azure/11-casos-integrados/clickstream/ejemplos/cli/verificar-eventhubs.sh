#!/usr/bin/env bash
# Revisa el estado del flujo de clics. Solo lectura. Requiere: az login.
set -euo pipefail

ENTORNO="${1:?uso: $0 <dev|prod>}"
RG="rg-clics-${ENTORNO}"
NS="evhns-clics-${ENTORNO}"

echo "== Espacio de nombres: nivel, unidades y auto-inflate =="
az eventhubs namespace show -g "$RG" -n "$NS" \
  --query "{sku:sku.name, unidades:sku.capacity, autoInflate:isAutoInflateEnabled, maximo:maximumThroughputUnits, claves:disableLocalAuth}" -o table

echo "== Event hub: particiones, retención y Capture =="
az eventhubs eventhub show -g "$RG" --namespace-name "$NS" -n clics \
  --query "{particiones:partitionCount, retencionDias:retentionDescription.retentionTimeInHours, capture:captureDescription.enabled}" -o table

echo "== Grupos de consumidores =="
az eventhubs eventhub consumer-group list -g "$RG" --namespace-name "$NS" --eventhub-name clics --query "[].name" -o tsv

echo "== Métricas de la última hora: entrada, salida y limitaciones =="
ID=$(az eventhubs namespace show -g "$RG" -n "$NS" --query id -o tsv)
az monitor metrics list --resource "$ID" --metric IncomingMessages OutgoingMessages ThrottledRequests ServerErrors \
  --interval PT5M --aggregation Total --offset 1h \
  --query "value[].{metrica:name.value, total:sum(timeseries[0].data[].total)}" -o table 2>/dev/null \
  || echo "(ajusta el comando de métricas a tu versión de la CLI)"
