#!/usr/bin/env bash
# Firestore. Uso: ./firestore.sh <proyecto>
set -euo pipefail
P="${1:?proyecto}"
gcloud firestore databases list --project "$P" --format='table(name,locationId,type,deleteProtectionState)'
gcloud firestore indexes composite list --project "$P"
gcloud firestore fields ttls list --project "$P"
