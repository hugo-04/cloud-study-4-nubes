#!/usr/bin/env bash
# Cloud SQL. Uso: ./cloudsql.sh <proyecto> <instancia>
set -euo pipefail
P="${1:?proyecto}"; I="${2:?instancia}"
gcloud sql instances describe "$I" --project "$P" --format='value(connectionName,settings.availabilityType,settings.ipConfiguration.ipv4Enabled)'
gcloud sql users list --instance "$I" --project "$P"
gcloud sql backups list --instance "$I" --project "$P" --limit 3
