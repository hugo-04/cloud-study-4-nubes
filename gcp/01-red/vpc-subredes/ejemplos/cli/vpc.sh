#!/usr/bin/env bash
# Inventario de red. Uso: ./vpc.sh <proyecto> [red]
set -euo pipefail
P="${1:?proyecto}"; R="${2:-modalima-vpc}"
gcloud compute networks describe "$R" --project "$P" --format='table(name,autoCreateSubnetworks,routingConfig.routingMode,mtu)'
gcloud compute networks subnets list --project "$P" --network "$R" \
  --format='table(name,region.basename(),ipCidrRange,privateIpGoogleAccess,secondaryIpRanges[].ipCidrRange.list())'
