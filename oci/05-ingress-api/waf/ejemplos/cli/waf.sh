#!/usr/bin/env bash
# Operación del WAF. Uso: ./waf.sh <compartment-ocid> [policy-ocid]
set -euo pipefail
C="${1:?compartment ocid}"
echo "== Firewalls"
oci waf web-app-firewall list -c "$C" --all \
  --query 'data.items[].{nombre:"display-name",estado:"lifecycle-state",politica:"web-app-firewall-policy-id"}' --output table
if [ -n "${2:-}" ]; then
  echo "== Acciones de la política"
  oci waf web-app-firewall-policy get --web-app-firewall-policy-id "$2" --query 'data.actions[].{nombre:name,tipo:type}' --output table
fi
echo "== Capacidades disponibles:  oci waf protection-capability list -c $C --all --output table"
