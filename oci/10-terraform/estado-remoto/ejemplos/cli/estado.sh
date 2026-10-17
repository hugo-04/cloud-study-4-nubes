#!/usr/bin/env bash
# Inventario del bucket de estado. Uso: ./estado.sh <bucket> [prefijo]
set -euo pipefail
B="${1:?bucket}"; P="${2:-}"
oci os bucket get -bn "$B" --query 'data.{versionado:versioning,publico:"public-access-type",cmk:"kms-key-id"}' --output table
oci os object list -bn "$B" --prefix "$P" --all --fields name,size,timeModified \
  --query 'data[].{objeto:name,bytes:size,modificado:"time-modified"}' --output table
echo "== Versiones anteriores:  oci os object list-object-versions -bn $B --prefix <clave>"
