#!/usr/bin/env bash
# Estado remoto. Uso: ./estado.sh <bucket>
set -euo pipefail
B="${1:?bucket}"
gcloud storage buckets describe "gs://$B" --format='yaml(versioning,iamConfiguration,defaultKmsKeyName)'
gcloud storage ls -l "gs://$B/**"
gcloud storage ls -a "gs://$B/**default.tfstate" | tail -5
