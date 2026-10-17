#!/usr/bin/env bash
# Secret Manager. Uso: ./secretos.sh <proyecto> <secreto>
set -euo pipefail
P="${1:?proyecto}"; S="${2:?secreto}"
gcloud secrets describe "$S" --project "$P" --format='yaml(replication,rotation,topics)'
gcloud secrets versions list "$S" --project "$P" --format='table(name,state,createTime)'
gcloud secrets get-iam-policy "$S" --project "$P" --format='table(bindings.role,bindings.members)'
echo "== Leer (solo para diagnóstico, nunca en logs):  gcloud secrets versions access latest --secret=$S --project=$P"
