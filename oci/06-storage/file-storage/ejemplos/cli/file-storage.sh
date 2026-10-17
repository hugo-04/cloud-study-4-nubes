#!/usr/bin/env bash
# File Storage: inventario y montaje. Uso: ./file-storage.sh <compartment-ocid> <ad> [ip-mount-target] [export]
set -euo pipefail
C="${1:?compartment}"; AD="${2:?availability domain}"
echo "== File systems"
oci fs file-system list -c "$C" --availability-domain "$AD" --all \
  --query 'data[].{nombre:"display-name",bytes:"metered-bytes",estado:"lifecycle-state"}' --output table
echo "== Exports"
oci fs export list -c "$C" --all --query 'data[].{ruta:path,id:id}' --output table
if [ -n "${3:-}" ]; then
  echo "== Montaje de prueba (requiere nfs-utils y root)"
  echo "sudo mkdir -p /mnt/media && sudo mount -t nfs -o nosuid,resvport ${3}:${4:-/catalogo-media} /mnt/media"
fi
