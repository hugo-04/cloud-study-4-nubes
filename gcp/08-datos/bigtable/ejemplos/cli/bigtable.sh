#!/usr/bin/env bash
# Bigtable. Uso: ./bigtable.sh <proyecto> <instancia>
set -euo pipefail
P="${1:?proyecto}"; I="${2:?instancia}"
gcloud bigtable instances describe "$I" --project "$P"
gcloud bigtable clusters list --instances "$I" --project "$P"
cbt -project "$P" -instance "$I" read lecturas prefix='maquina-017#' count=5
