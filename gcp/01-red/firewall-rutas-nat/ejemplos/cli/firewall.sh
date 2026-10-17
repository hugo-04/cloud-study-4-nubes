#!/usr/bin/env bash
# Reglas de firewall y NAT. Uso: ./firewall.sh <proyecto> <red> <region>
set -euo pipefail
P="${1:?proyecto}"; N="${2:?red}"; R="${3:?region}"
gcloud compute firewall-rules list --project "$P" --filter="network:$N" --sort-by=priority \
  --format='table(name,direction,priority,sourceRanges.list(),allowed[].map().firewall_rule().list(),targetServiceAccounts.list(),targetTags.list(),disabled)'
gcloud compute routers list --project "$P" --regions "$R" --format='table(name,network.basename())'
echo "== Estado de NAT:  gcloud compute routers get-nat-mapping-info <router> --region $R --project $P"
