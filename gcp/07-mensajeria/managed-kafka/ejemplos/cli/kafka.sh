#!/usr/bin/env bash
# Managed Kafka. Uso: ./kafka.sh <proyecto> <region> <cluster>
set -euo pipefail
P="${1:?proyecto}"; R="${2:?region}"; C="${3:?cluster}"
gcloud managed-kafka clusters describe "$C" --project "$P" --location "$R" --format='value(state,capacityConfig)'
gcloud managed-kafka topics list --project "$P" --location "$R" --cluster "$C"
gcloud managed-kafka consumer-groups list --project "$P" --location "$R" --cluster "$C"
