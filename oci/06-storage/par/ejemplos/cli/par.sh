#!/usr/bin/env bash
# PAR con la CLI. Uso: ./par.sh <bucket> <objeto>
set -euo pipefail
B="${1:?bucket}"; O="${2:?objeto}"
VENCE=$(date -u -d '+15 minutes' +%Y-%m-%dT%H:%M:%SZ)
echo "== Crear PAR de lectura (vence $VENCE); la URL se muestra UNA vez"
oci os preauth-request create -bn "$B" --name "descarga-$(date +%s)" --access-type ObjectRead \
  --object-name "$O" --time-expires "$VENCE" --query 'data.{id:id,uri:"access-uri"}'
echo "== PAR vivas del bucket"
oci os preauth-request list -bn "$B" --all --query 'data[].{id:id,nombre:name,tipo:"access-type",vence:"time-expires"}' --output table
echo "== Revocar:  oci os preauth-request delete -bn $B --par-id <id> --force"
