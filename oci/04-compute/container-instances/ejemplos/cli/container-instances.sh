#!/usr/bin/env bash
# Operación de Container Instances con la CLI de OCI. Uso: ./container-instances.sh <compartment-ocid> [instance-ocid]
set -euo pipefail
C="${1:?compartment ocid}"
echo "== Instancias (nombre, estado)"
oci container-instances container-instance list -c "$C" --all \
  --query 'data.items[].{nombre:"display-name",estado:"lifecycle-state",id:id}' --output table
if [ -n "${2:-}" ]; then
  echo "== Contenedores de la instancia"
  oci container-instances container list -c "$C" --container-instance-id "$2" \
    --query 'data.items[].{nombre:"display-name",estado:"lifecycle-state",salida:"exit-code",id:id}' --output table
  echo "== Registros:  oci container-instances container retrieve-logs --container-id <id> --file -"
fi
echo "== Limpieza de inactivas:  oci container-instances container-instance delete --container-instance-id <id> --force"
