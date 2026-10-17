#!/usr/bin/env bash
# Pub/Sub. Uso: ./pubsub.sh <proyecto> <tema> <suscripcion>
set -euo pipefail
P="${1:?proyecto}"; T="${2:?tema}"; S="${3:?suscripcion}"
gcloud pubsub topics publish "$T" --project "$P" --message='{"pedido":"P-100"}' --attribute=tipo=fisico --ordering-key=C-9
gcloud pubsub subscriptions pull "$S" --project "$P" --limit=5 --auto-ack
gcloud pubsub subscriptions describe "$S" --project "$P" --format='yaml(ackDeadlineSeconds,enableMessageOrdering,deadLetterPolicy,filter)'
