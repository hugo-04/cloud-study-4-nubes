#!/usr/bin/env bash
# Operación de Queue. Uso: ./queue.sh <queue-ocid>
set -euo pipefail
Q="${1:?queue ocid}"
EP=$(oci queue queue-admin queue get --queue-id "$Q" --query 'data."messages-endpoint"' --raw-output)
echo "== Endpoint de mensajes: $EP"
oci queue messages get-stats --queue-id "$Q" --endpoint "$EP"
echo "== Enviar prueba"
oci queue messages put-messages --queue-id "$Q" --endpoint "$EP" --messages '[{"content":"{\"pedido\":\"P-100\"}"}]'
echo "== Leer (long polling 10 s, visibilidad 60 s)"
oci queue messages get-messages --queue-id "$Q" --endpoint "$EP" --timeout-in-seconds 10 --visibility-in-seconds 60 --limit 5
