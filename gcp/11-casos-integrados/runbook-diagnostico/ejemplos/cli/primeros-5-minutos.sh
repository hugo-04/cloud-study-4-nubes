#!/usr/bin/env bash
# Primeros 5 minutos. Uso: ./primeros-5-minutos.sh <proyecto> <region> <servicio_run>
set -euo pipefail
P="${1:?proyecto}"; R="${2:?region}"; S="${3:?servicio}"
echo "== Errores recientes del LB (5xx)"
gcloud logging read 'resource.type="http_load_balancer" AND httpRequest.status>=500' --project "$P" --freshness 10m --limit 10 \
  --format='table(timestamp,httpRequest.status,jsonPayload.statusDetails)'
echo "== Revisiones y tráfico de Cloud Run"
gcloud run services describe "$S" --region "$R" --project "$P" --format='yaml(status.traffic)'
gcloud run revisions list --service "$S" --region "$R" --project "$P" --limit 3
echo "== Cambios recientes (Admin Activity, 2 h)"
gcloud logging read 'logName:"cloudaudit.googleapis.com%2Factivity"' --project "$P" --freshness 2h --limit 10 \
  --format='table(timestamp,protoPayload.authenticationInfo.principalEmail,protoPayload.methodName)'
echo "== Mitigación (no se ejecuta sola): gcloud run services update-traffic $S --to-revisions=<anterior>=100 --region $R"
