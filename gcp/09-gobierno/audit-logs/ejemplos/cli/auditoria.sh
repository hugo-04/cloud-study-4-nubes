#!/usr/bin/env bash
# Audit Logs. Uso: ./auditoria.sh <proyecto>
set -euo pipefail
P="${1:?proyecto}"
gcloud logging read 'logName:"cloudaudit.googleapis.com%2Factivity" AND protoPayload.methodName:"SetIamPolicy"' \
  --project "$P" --freshness 7d --limit 10 \
  --format='table(timestamp,protoPayload.authenticationInfo.principalEmail,protoPayload.resourceName)'
gcloud projects get-iam-policy "$P" --format='yaml(auditConfigs)'
gcloud logging sinks list --project "$P"
