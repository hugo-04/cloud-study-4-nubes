#!/usr/bin/env bash
# Org Policy. Uso: ./orgpolicy.sh <proyecto>
set -euo pipefail
P="${1:?proyecto}"
for c in sql.restrictPublicIp compute.vmExternalIpAccess iam.disableServiceAccountKeyCreation gcp.resourceLocations; do
  echo "== $c"; gcloud org-policies describe "$c" --effective --project "$P" --format=yaml
done
