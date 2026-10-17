#!/usr/bin/env bash
# Inventario de gobierno. Uso: ./gobierno.sh <tenancy-ocid>
set -euo pipefail
T="${1:?tenancy ocid}"
echo "== Compartimentos (árbol completo)"
oci iam compartment list -c "$T" --compartment-id-in-subtree true --access-level ANY --all \
  --query 'data[?"lifecycle-state"==`ACTIVE`].{nombre:name,padre:"compartment-id"}' --output table
echo "== Espacios de etiquetas"
oci iam tag-namespace list -c "$T" --all --query 'data[].{nombre:name,retirado:"is-retired"}' --output table
echo "== Cuotas"
oci limits quota list -c "$T" --all --query 'data[].{nombre:name,id:id}' --output table
