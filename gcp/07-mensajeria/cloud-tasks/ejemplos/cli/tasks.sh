#!/usr/bin/env bash
# Cloud Tasks. Uso: ./tasks.sh <proyecto> <region> <cola> <url> <sa>
set -euo pipefail
P="${1:?proyecto}"; R="${2:?region}"; Q="${3:?cola}"; U="${4:?url}"; SA="${5:?sa}"
gcloud tasks queues describe "$Q" --location "$R" --project "$P" --format='yaml(rateLimits,retryConfig,state)'
gcloud tasks create-http-task "prueba-$(date +%s)" --queue "$Q" --location "$R" --project "$P" \
  --url "$U" --method POST --body-content '{"carrito":"C-1"}' --oidc-service-account-email "$SA"
