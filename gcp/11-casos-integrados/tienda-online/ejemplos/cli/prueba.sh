#!/usr/bin/env bash
# Prueba de punta a punta. Uso: ./prueba.sh <proyecto> <url_tienda>
set -euo pipefail
P="${1:?proyecto}"; U="${2:?url}"
TOKEN=$(gcloud auth print-identity-token)
curl -fsS -X POST "$U/tienda/pedidos" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"idPedido":"P-1001","total":"129.90"}'
curl -fsS -X POST "$U/tienda/pedidos/relay" -H "Authorization: Bearer $TOKEN"
gcloud pubsub subscriptions describe facturacion --project "$P" --format='value(name,deadLetterPolicy.deadLetterTopic)'
gcloud pubsub subscriptions pull facturacion-dlq-monitor --project "$P" --limit 5 2>/dev/null || true
