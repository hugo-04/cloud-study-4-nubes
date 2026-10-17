#!/usr/bin/env bash
# Filestore. Uso: ./filestore.sh <proyecto>
set -euo pipefail
P="${1:?proyecto}"
gcloud filestore instances list --project "$P" --format='table(name.basename(),tier,fileShares[0].name,fileShares[0].capacityGb,networks[0].ipAddresses[0])'
gcloud filestore instances list --project "$P" --format='yaml(fileShares[].nfsExportOptions)'
