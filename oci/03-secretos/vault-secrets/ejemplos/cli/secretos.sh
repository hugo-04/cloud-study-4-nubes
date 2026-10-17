#!/usr/bin/env bash
# Operación de secretos con la CLI de OCI. Uso: ./secretos.sh <compartment-ocid> [secret-ocid]
set -euo pipefail
C="${1:?compartment ocid}"
echo "== Secretos"
oci vault secret list -c "$C" --all --query 'data[].{nombre:"secret-name",estado:"lifecycle-state",id:id}' --output table
if [ -n "${2:-}" ]; then
  echo "== Metadatos de la versión vigente (sin imprimir el valor)"
  oci secrets secret-bundle get --secret-id "$2" --stage CURRENT \
    --query 'data.{version:"version-number",etapas:stages,creado:"time-created"}'
fi
