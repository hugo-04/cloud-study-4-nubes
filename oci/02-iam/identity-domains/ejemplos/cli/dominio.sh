#!/usr/bin/env bash
# Operación de dominios con la CLI de OCI. Uso: ./dominio.sh <compartment-ocid>
set -euo pipefail
C="${1:?compartment ocid}"
echo "== Dominios"
oci iam domain list -c "$C" --all --query 'data[].{nombre:"display-name",url:url,tipo:type,estado:"lifecycle-state"}' --output table
echo "== Grupos del dominio Default (API de OCI IAM)"
oci iam group list -c "$C" --all --query 'data[].{nombre:name,id:id}' --output table
