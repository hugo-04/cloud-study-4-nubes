#!/usr/bin/env bash
# Costos del mes por servicio. Uso: ./costos.sh <tenancy-ocid>
set -euo pipefail
T="${1:?tenancy ocid}"
INI=$(date -u +%Y-%m-01T00:00:00Z); FIN=$(date -u -d tomorrow +%Y-%m-%dT00:00:00Z)
oci usage-api usage-summary request-summarized-usages --tenant-id "$T" --granularity MONTHLY --query-type COST \
  --time-usage-started "$INI" --time-usage-ended "$FIN" --group-by '["service"]' \
  --query 'data.items[].{servicio:service,costo:"computed-amount",moneda:currency}' --output table
echo "== Presupuestos"
oci budgets budget list -c "$T" --all --query 'data[].{nombre:"display-name",monto:amount,real:"actual-spend",proyectado:"forecasted-spend"}' --output table
