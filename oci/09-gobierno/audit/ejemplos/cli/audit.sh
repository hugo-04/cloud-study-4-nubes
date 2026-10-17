#!/usr/bin/env bash
# Audit. Uso: ./audit.sh <compartment-ocid> [horas]
set -euo pipefail
C="${1:?compartment}"; H="${2:-24}"
INI=$(date -u -d "-$H hours" +%Y-%m-%dT%H:%M:%SZ); FIN=$(date -u +%Y-%m-%dT%H:%M:%SZ)
oci audit event list -c "$C" --start-time "$INI" --end-time "$FIN" --all \
  --query 'data[?contains(data."event-name",`Delete`) || contains(data."event-name",`Policy`)].{cuando:"event-time",que:data."event-name",quien:data.identity."principal-name",ip:data.identity."ip-address",recurso:data."resource-name"}' \
  --output table
