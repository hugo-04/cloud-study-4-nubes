#!/usr/bin/env bash
# Diagnóstico del Load Balancer. Uso: ./load-balancer.sh <lb-ocid> <backend-set>
set -euo pipefail
LB="${1:?lb ocid}"; BS="${2:?backend set}"
echo "== Salud general"
oci lb load-balancer-health get --load-balancer-id "$LB" --query 'data.status' --raw-output
echo "== Salud del backend set $BS"
oci lb backend-set-health get --load-balancer-id "$LB" --backend-set-name "$BS"
echo "== Backends"
oci lb backend list --load-balancer-id "$LB" --backend-set-name "$BS" \
  --query 'data[].{nombre:name,drain:drain,offline:offline,peso:weight}' --output table
echo "== Drenar uno:  oci lb backend update --load-balancer-id $LB --backend-set-name $BS --backend-name IP:PUERTO --drain true --weight 1 --backup false --offline false"
