#!/usr/bin/env bash
# Diagnóstico. Uso: ./clicks.sh <proyecto> <region> <cluster>
set -euo pipefail
P="${1:?proyecto}"; R="${2:?region}"; C="${3:?cluster}"
gcloud managed-kafka topics describe clickstream --cluster "$C" --location "$R" --project "$P"
gcloud managed-kafka consumer-groups describe tablero --cluster "$C" --location "$R" --project "$P"
