#!/usr/bin/env bash
# Inspecciona un ticket de claim check. Uso: ./claim-check.sh <bucket> <objeto> <sha256-esperado>
set -euo pipefail
B="${1:?bucket}"; O="${2:?objeto}"; H="${3:?sha256}"
oci os object head -bn "$B" --name "$O"
oci os object get -bn "$B" --name "$O" --file /tmp/carga.bin
R=$(sha256sum /tmp/carga.bin | cut -d' ' -f1)
[ "$R" = "$H" ] && echo "huella OK" || { echo "huella distinta: $R"; exit 1; }
