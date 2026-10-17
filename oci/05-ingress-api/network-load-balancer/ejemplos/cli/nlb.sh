#!/usr/bin/env bash
# Diagnóstico del Network Load Balancer. Uso: ./nlb.sh <nlb-ocid> <backend-set>
set -euo pipefail
N="${1:?nlb ocid}"; BS="${2:?backend set}"
echo "== Salud general"
oci nlb network-load-balancer-health get --network-load-balancer-id "$N" --query 'data.status' --raw-output
echo "== Salud del set $BS"
oci nlb backend-set-health get --network-load-balancer-id "$N" --backend-set-name "$BS"
echo "== Backends"
oci nlb backend list --network-load-balancer-id "$N" --backend-set-name "$BS" \
  --query 'data.items[].{nombre:name,drain:"is-drain",offline:"is-offline"}' --output table
