#!/usr/bin/env bash
# Cloud Run. Uso: ./run.sh <proyecto> <region> <servicio>
set -euo pipefail
P="${1:?proyecto}"; R="${2:?region}"; S="${3:?servicio}"
gcloud run services describe "$S" --project "$P" --region "$R" --format='yaml(status.url,status.traffic,spec.template.spec.serviceAccountName)'
URL=$(gcloud run services describe "$S" --project "$P" --region "$R" --format='value(status.url)')
curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $(gcloud auth print-identity-token --audiences="$URL")" "$URL/actuator/health"
echo "== Canario:  gcloud run services update-traffic $S --to-revisions=<nueva>=10 --region $R"
