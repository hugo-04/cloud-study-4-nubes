#!/usr/bin/env bash
# Genera clics de prueba. Uso: ./clicks.sh <stream-ocid> [cantidad]
set -euo pipefail
S="${1:?stream}"; N="${2:-20}"
EP=$(oci streaming admin stream get --stream-id "$S" --query 'data."messages-endpoint"' --raw-output)
MSGS="["
for i in $(seq 1 "$N"); do
  SES="s-$((RANDOM % 5))"; V=$(printf '{"tipo":"vista","sku":"POL-0%d","ts":"%s"}' $((RANDOM % 3)) "$(date -u +%FT%TZ)" | base64 -w0)
  MSGS+="{\"key\":\"$(printf %s "$SES" | base64 -w0)\",\"value\":\"$V\"},"
done
oci streaming stream message put --stream-id "$S" --endpoint "$EP" --messages "${MSGS%,}]"
