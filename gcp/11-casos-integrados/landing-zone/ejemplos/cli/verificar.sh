#!/usr/bin/env bash
# Verificación. Uso: ./verificar.sh <host> <proyecto_prod> <proyecto_dev>
set -euo pipefail
H="${1:?host}"; P="${2:?prod}"; D="${3:?dev}"
gcloud compute shared-vpc associated-projects list "$H"
gcloud compute networks subnets list --project "$H" --filter='name~^tostaduria' --format='table(name,region,ipCidrRange,secondaryIpRanges.list())'
for x in "$P" "$D"; do
  gcloud billing projects describe "$x" --format='value(billingEnabled)'
  gcloud projects describe "$x" --format='value(labels)'
done
