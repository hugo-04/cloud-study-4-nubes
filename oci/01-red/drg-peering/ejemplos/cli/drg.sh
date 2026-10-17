#!/usr/bin/env bash
# Inspección de una DRG. Uso: ./drg.sh <compartment-ocid> <drg-ocid>
set -euo pipefail
C="${1:?compartment}"; D="${2:?drg}"
oci network drg get --drg-id "$D" --query 'data.{nombre:"display-name",estado:"lifecycle-state"}' --output table
echo "== Adjuntos"
oci network drg-attachment list -c "$C" --drg-id "$D" --all \
  --query 'data[].{nombre:"display-name",tipo:"network-details".type,estado:"lifecycle-state"}' --output table
echo "== Tablas de rutas de la DRG"
oci network drg-route-table list --drg-id "$D" --all --query 'data[].{nombre:"display-name",id:id}' --output table
