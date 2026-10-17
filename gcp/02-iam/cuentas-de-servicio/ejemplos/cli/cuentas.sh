#!/usr/bin/env bash
# Cuentas de servicio. Uso: ./cuentas.sh <proyecto> [cuenta-a-suplantar]
set -euo pipefail
P="${1:?proyecto}"
gcloud iam service-accounts list --project "$P" --format='table(email,disabled)'
echo "== Llaves gestionadas por usuarios (deberían ser 0)"
for sa in $(gcloud iam service-accounts list --project "$P" --format='value(email)'); do
  n=$(gcloud iam service-accounts keys list --iam-account "$sa" --managed-by=user --format='value(name)' | wc -l); [ "$n" -gt 0 ] && echo "$sa: $n"
done
[ -n "${2:-}" ] && gcloud storage ls --project "$P" --impersonate-service-account="$2"
