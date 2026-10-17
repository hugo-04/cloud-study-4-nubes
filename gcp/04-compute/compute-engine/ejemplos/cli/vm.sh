#!/usr/bin/env bash
# VMs. Uso: ./vm.sh <proyecto> [vm] [zona]
set -euo pipefail
P="${1:?proyecto}"
gcloud compute instances list --project "$P" --format='table(name,zone.basename(),status,networkInterfaces[0].accessConfigs[0].natIP:label=IP_EXTERNA,serviceAccounts[0].email)'
[ -n "${2:-}" ] && gcloud compute ssh "$2" --zone "${3:?zona}" --project "$P" --tunnel-through-iap
