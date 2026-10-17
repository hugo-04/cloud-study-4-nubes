#!/usr/bin/env bash
# URL firmada con suplantación (sin llaves). Uso: ./firmadas.sh <bucket> <objeto> <sa-firmante>
set -euo pipefail
B="${1:?bucket}"; O="${2:?objeto}"; SA="${3:?cuenta firmante}"
gcloud storage sign-url "gs://$B/$O" --duration=10m --http-verb=GET --impersonate-service-account="$SA"
