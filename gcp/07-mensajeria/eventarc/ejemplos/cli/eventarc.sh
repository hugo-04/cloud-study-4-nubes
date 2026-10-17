#!/usr/bin/env bash
# Eventarc. Uso: ./eventarc.sh <proyecto> <region>
set -euo pipefail
P="${1:?proyecto}"; R="${2:?region}"
gcloud eventarc triggers list --project "$P" --location "$R" --format='table(name.basename(),destination.cloudRun.service,serviceAccount,eventFilters.list())'
gcloud eventarc providers list --project "$P" --location "$R" --limit 5
