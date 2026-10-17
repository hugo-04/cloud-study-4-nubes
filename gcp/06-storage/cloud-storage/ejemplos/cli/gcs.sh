#!/usr/bin/env bash
# Cloud Storage. Uso: ./gcs.sh <bucket> [archivo]
set -euo pipefail
B="${1:?bucket}"
gcloud storage buckets describe "gs://$B" --format='yaml(location,default_storage_class,uniform_bucket_level_access,public_access_prevention,versioning_enabled)'
gcloud storage ls "gs://$B/pedidos/" | head
[ -n "${2:-}" ] && gcloud storage cp "$2" "gs://$B/pedidos/$(date +%Y/%m/%d)/$(basename "$2")" --if-generation-match=0
