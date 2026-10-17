#!/usr/bin/env bash
# Verifica la identidad desde un pod. Uso: ./wi.sh <namespace> <pod>
set -euo pipefail
NS="${1:?namespace}"; POD="${2:?pod}"
kubectl -n "$NS" exec "$POD" -- sh -c 'curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email; echo'
kubectl -n "$NS" get pod "$POD" -o jsonpath='{.spec.serviceAccountName}{"\n"}'
