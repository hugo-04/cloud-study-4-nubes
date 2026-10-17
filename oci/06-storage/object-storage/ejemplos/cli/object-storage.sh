#!/usr/bin/env bash
# Operación de Object Storage. Uso: ./object-storage.sh <bucket> [archivo]
set -euo pipefail
B="${1:?bucket}"
NS=$(oci os ns get --query data --raw-output)
echo "== Namespace: $NS"
oci os bucket get -bn "$B" --query 'data.{nivel:"storage-tier",publico:"public-access-type",versionado:versioning,eventos:"object-events-enabled"}' --output table
echo "== Últimos objetos bajo pedidos/"
oci os object list -bn "$B" --prefix pedidos/ --limit 10 --query 'data[].{nombre:name,tam:size}' --output table
if [ -n "${2:-}" ]; then
  echo "== Subida sin sobrescribir (multipart automático)"
  oci os object put -bn "$B" --file "$2" --name "pedidos/$(date +%Y/%m/%d)/$(basename "$2")" --no-overwrite
fi
