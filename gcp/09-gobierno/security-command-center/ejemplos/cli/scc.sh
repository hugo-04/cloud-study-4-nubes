#!/usr/bin/env bash
# SCC. Uso: ./scc.sh <organizacion>
set -euo pipefail
O="${1:?organizacion}"
gcloud scc findings list "organizations/$O" --location global \
  --filter 'state="ACTIVE" AND mute!="MUTED" AND (severity="CRITICAL" OR severity="HIGH")' \
  --format='table(finding.category,finding.severity,finding.resourceName.basename())' --limit 20
gcloud scc notifications list "organizations/$O" --location global
