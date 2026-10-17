#!/usr/bin/env bash
# Subida manual con PAR. Uso: ./subida.sh <bucket> <archivo>
set -euo pipefail
B="${1:?bucket}"; F="${2:?archivo}"; ID="S-$(date +%s)"
VENCE=$(date -u -d '+10 minutes' +%Y-%m-%dT%H:%M:%SZ)
URI=$(oci os preauth-request create -bn "$B" --name "subida-$ID" --access-type ObjectWrite \
  --object-name "cuarentena/$ID.jpg" --time-expires "$VENCE" --query 'data."full-path"' --raw-output)
curl -sf -X PUT --data-binary @"$F" "$URI" && echo "subido como cuarentena/$ID.jpg"
sleep 20; oci os object list -bn "$B" --prefix "aprobados/$ID" --query 'data[].name'
