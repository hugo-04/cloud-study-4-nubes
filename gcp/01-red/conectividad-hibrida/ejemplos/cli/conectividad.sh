#!/usr/bin/env bash
# Estado de conectividad. Uso: ./conectividad.sh <proyecto> <red> <region> [router]
set -euo pipefail
P="${1:?proyecto}"; N="${2:?red}"; R="${3:?region}"
gcloud compute networks peerings list --project "$P" --network "$N" --format='table(peerings[].name,peerings[].state,peerings[].exportCustomRoutes,peerings[].importCustomRoutes)'
gcloud compute vpn-tunnels list --project "$P" --regions "$R" --format='table(name,status,peerIp)'
[ -n "${4:-}" ] && gcloud compute routers get-status "$4" --region "$R" --project "$P" --format='table(result.bgpPeerStatus[].name,result.bgpPeerStatus[].status,result.bgpPeerStatus[].numLearnedRoutes)'
