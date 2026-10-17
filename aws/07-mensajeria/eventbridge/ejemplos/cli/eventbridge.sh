#!/usr/bin/env bash
# Comandos de ejemplo para EventBridge. Define BUS (nombre) y, para replay, ARCHIVE_ARN y BUS_ARN.
set -euo pipefail
BUS="${BUS:?define BUS}"

# 1) Probar el patrón contra un evento (sin desplegar nada)
aws events test-event-pattern \
  --event-pattern file://../json/patron-orden.json \
  --event file://../json/evento-ejemplo.json

# 2) Publicar (revisa FailedEntryCount en la respuesta)
aws events put-events --entries file://../json/entradas-putevents.json

# 3) Ver reglas y destinos de un bus
aws events list-rules --event-bus-name "$BUS"
# aws events list-targets-by-rule --rule prod-orden-grande --event-bus-name "$BUS"

# 4) Reproducir un rango archivado hacia el bus
# aws events start-replay --replay-name "reproceso-$(date +%s)" \
#   --event-source-arn "$ARCHIVE_ARN" \
#   --destination "{\"Arn\":\"$BUS_ARN\"}" \
#   --event-start-time 2026-10-14T00:00:00Z --event-end-time 2026-10-14T06:00:00Z

# 5) Fallos de entrega de una regla (últimas 3 horas)
aws cloudwatch get-metric-statistics --namespace AWS/Events --metric-name FailedInvocations \
  --dimensions Name=RuleName,Value=prod-orden-grande Name=EventBusName,Value="$BUS" \
  --start-time "$(date -u -d '-3 hours' +%FT%TZ)" --end-time "$(date -u +%FT%TZ)" \
  --period 300 --statistics Sum
