#!/usr/bin/env bash
# Prueba de punta a punta. Uso: ./prueba.sh <host-tienda> <token> <queue-ocid>
set -euo pipefail
H="${1:?host}"; T="${2:?token}"; Q="${3:?queue}"
echo "== Crear pedido"
curl -sf -X POST "https://$H/v1/pedidos" -H "Authorization: Bearer $T" -H 'Content-Type: application/json' \
  -d '{"carrito":"actual","pago":"tok_prueba"}'
echo; echo "== Mensajes en la cola de facturación"
EP=$(oci queue queue-admin queue get --queue-id "$Q" --query 'data."messages-endpoint"' --raw-output)
oci queue messages get-stats --queue-id "$Q" --endpoint "$EP"
