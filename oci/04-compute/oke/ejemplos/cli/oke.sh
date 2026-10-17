#!/usr/bin/env bash
# Operación de OKE con la CLI de OCI. Uso: ./oke.sh <compartment-ocid> [cluster-ocid]
set -euo pipefail
C="${1:?compartment ocid}"
echo "== Clústeres"
oci ce cluster list -c "$C" --all --query 'data[].{nombre:name,version:"kubernetes-version",tipo:type,estado:"lifecycle-state"}' --output table
if [ -n "${2:-}" ]; then
  echo "== Node pools"
  oci ce node-pool list -c "$C" --cluster-id "$2" --all --query 'data[].{nombre:name,version:"kubernetes-version",forma:"node-shape"}' --output table
  echo "== Kubeconfig (endpoint privado)"
  oci ce cluster create-kubeconfig --cluster-id "$2" --file "$HOME/.kube/config" --kube-endpoint PRIVATE_ENDPOINT --token-version 2.0.0
fi
