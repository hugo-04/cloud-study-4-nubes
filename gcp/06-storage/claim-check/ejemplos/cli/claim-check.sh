#!/usr/bin/env bash
# Verifica un ticket. Uso: ./claim-check.sh <bucket> <objeto> <generacion> <sha256>
set -euo pipefail
gcloud storage cp "gs://${1:?bucket}/${2:?objeto}#${3:?generacion}" /tmp/carga.bin
R=$(sha256sum /tmp/carga.bin | cut -d' ' -f1); [ "$R" = "${4:?sha}" ] && echo "huella OK" || { echo "huella distinta"; exit 1; }
