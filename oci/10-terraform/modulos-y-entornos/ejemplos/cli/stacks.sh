#!/usr/bin/env bash
# Stacks de Resource Manager. Uso: ./stacks.sh <compartment-ocid> [stack-ocid]
set -euo pipefail
C="${1:?compartment}"
oci resource-manager stack list -c "$C" --all --query 'data[].{nombre:"display-name",tf:"terraform-version",estado:"lifecycle-state"}' --output table
if [ -n "${2:-}" ]; then
  echo "== Detectar drift"; oci resource-manager stack detect-drift --stack-id "$2"
  echo "== Plan:  oci resource-manager job create-plan-job --stack-id $2"
fi
