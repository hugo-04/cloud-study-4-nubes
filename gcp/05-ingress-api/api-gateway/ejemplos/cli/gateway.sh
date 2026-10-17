#!/usr/bin/env bash
# API Gateway. Uso: ./gateway.sh <proyecto> <region>
set -euo pipefail
P="${1:?proyecto}"; R="${2:?region}"
gcloud api-gateway apis list --project "$P" --format='table(name.basename(),state,managedService)'
gcloud api-gateway gateways list --project "$P" --location "$R" --format='table(name.basename(),apiConfig.basename(),defaultHostname,state)'
