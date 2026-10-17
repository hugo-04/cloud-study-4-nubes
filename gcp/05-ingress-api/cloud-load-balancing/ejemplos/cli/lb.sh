#!/usr/bin/env bash
# Balanceador. Uso: ./lb.sh <proyecto> <url-map> [backend-service]
set -euo pipefail
P="${1:?proyecto}"; M="${2:?url map}"
gcloud compute url-maps describe "$M" --project "$P" --format='yaml(hostRules,pathMatchers[].pathRules)'
gcloud compute url-maps validate --source=<(gcloud compute url-maps export "$M" --project "$P") --project "$P" || true
[ -n "${3:-}" ] && gcloud compute backend-services get-health "$3" --global --project "$P"
