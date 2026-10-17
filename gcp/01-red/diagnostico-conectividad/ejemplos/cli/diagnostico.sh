#!/usr/bin/env bash
# Prueba de conectividad. Uso: ./diagnostico.sh <proyecto> <vm-origen-uri> <ip-destino> <puerto>
set -euo pipefail
P="${1:?proyecto}"; O="${2:?vm origen}"; D="${3:?ip destino}"; PT="${4:?puerto}"
N="prueba-$(date +%s)"
gcloud network-management connectivity-tests create "$N" --project "$P" \
  --source-instance="$O" --destination-ip-address="$D" --destination-port="$PT" --protocol=TCP
gcloud network-management connectivity-tests describe "$N" --project "$P" \
  --format='yaml(reachabilityDetails.result,reachabilityDetails.traces[0].steps[-1])'
