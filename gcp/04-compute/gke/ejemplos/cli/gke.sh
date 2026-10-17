#!/usr/bin/env bash
# GKE. Uso: ./gke.sh <proyecto> [cluster] [region]
set -euo pipefail
P="${1:?proyecto}"
gcloud container clusters list --project "$P" --format='table(name,location,currentMasterVersion,releaseChannel.channel,autopilot.enabled,privateClusterConfig.enablePrivateNodes)'
if [ -n "${2:-}" ]; then
  gcloud container clusters get-credentials "$2" --region "${3:?region}" --project "$P"
  kubectl get nodes -o wide; kubectl get pdb -A
fi
