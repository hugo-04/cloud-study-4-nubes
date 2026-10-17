#!/usr/bin/env bash
# IAM del proyecto. Uso: ./iam.sh <proyecto> [principal] [permiso] [recurso]
set -euo pipefail
P="${1:?proyecto}"
gcloud projects get-iam-policy "$P" --flatten='bindings[].members' --format='table(bindings.role,bindings.members,bindings.condition.title)'
if [ -n "${2:-}" ]; then
  gcloud policy-troubleshoot iam "${4:?recurso}" --principal-email="$2" --permission="${3:?permiso}"
fi
