#!/usr/bin/env bash
# Primeros 5 minutos de un incidente en la tienda: captura el estado de cada capa. SOLO LECTURA.
# Requiere: az login, kubectl apuntando al clúster y permisos de lectura. No imprime secretos.
set -uo pipefail

ENTORNO="${1:?uso: $0 <dev|prod>}"
RG="rg-tienda-${ENTORNO}"
SB="sb-tienda-${ENTORNO}"
AKS="aks-tienda-${ENTORNO}"
NS="tienda"

sec() { printf '\n==== %s ====\n' "$1"; }

sec "0. ¿Qué cambió? Operaciones de las últimas 2 horas (despliegues, reglas, bloqueos)"
az monitor activity-log list --resource-group "$RG" --offset 2h \
  --query "[?contains(['Write','Delete','Action'], authorization.action) || status.value!='Succeeded'].{hora:eventTimestamp, quien:caller, operacion:operationName.localizedValue, estado:status.value}" \
  -o table 2>/dev/null | head -25

sec "1. Salud de los servicios de Azure en la región"
az rest --method get \
  --url "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/providers/Microsoft.ResourceHealth/availabilityStatuses?api-version=2022-10-01&\$filter=resourceGroup eq '${RG}'" \
  --query "value[?properties.availabilityState!='Available'].{recurso:id, estado:properties.availabilityState, motivo:properties.summary}" \
  -o table 2>/dev/null || echo "(sin acceso a Resource Health o todo disponible)"

sec "2. AKS: pods que no están sanos"
kubectl get pods -n "$NS" --no-headers 2>/dev/null | awk '$3!="Running" || $4>3 {print}' | head -20
kubectl get events -n "$NS" --field-selector type=Warning --sort-by=.lastTimestamp 2>/dev/null | tail -10

sec "3. Service Bus: mensajes fallidos y activos por suscripción"
for TOPICO in $(az servicebus topic list -g "$RG" --namespace-name "$SB" --query "[].name" -o tsv 2>/dev/null); do
  az servicebus topic subscription list -g "$RG" --namespace-name "$SB" --topic-name "$TOPICO" \
    --query "[].{topico:'${TOPICO}', suscripcion:name, activos:countDetails.activeMessageCount, fallidos:countDetails.deadLetterMessageCount}" \
    -o table 2>/dev/null
done

sec "4. AKS: reinicios recientes por pod"
kubectl get pods -n "$NS" -o custom-columns=POD:.metadata.name,REINICIOS:.status.containerStatuses[0].restartCount,ESTADO:.status.phase 2>/dev/null | head -20

echo
echo "Siguiente: ejecuta la sonda sintética desde un pod (kubectl apply -f k8s/pod-diagnostico.yaml) y sigue el runbook por síntoma."
