#!/usr/bin/env bash
# Operación de API Gateway. Uso: ./api-gateway.sh <compartment-ocid> [host-del-gateway] [token]
set -euo pipefail
C="${1:?compartment ocid}"
echo "== Deployments"
oci api-gateway deployment list -c "$C" --all \
  --query 'data.items[].{nombre:"display-name",prefijo:"path-prefix",estado:"lifecycle-state",endpoint:endpoint}' --output table
if [ -n "${2:-}" ]; then
  echo "== Catálogo (anónimo)"; curl -s -o /dev/null -w '%{http_code}\n' "https://$2/v1/catalogo/destacados"
  echo "== Pedido (con token)"; curl -s -o /dev/null -w '%{http_code}\n' -X POST -H "Authorization: Bearer ${3:-}" "https://$2/v1/pedidos"
fi
