#!/usr/bin/env bash
# Funciones. Uso: ./funciones.sh <proyecto> <region> [funcion]
set -euo pipefail
P="${1:?proyecto}"; R="${2:?region}"
gcloud functions list --project "$P" --regions "$R" --v2 --format='table(name,state,buildConfig.runtime,serviceConfig.ingressSettings,serviceConfig.maxInstanceCount)'
[ -n "${3:-}" ] && gcloud functions logs read "$3" --project "$P" --region "$R" --limit 20
