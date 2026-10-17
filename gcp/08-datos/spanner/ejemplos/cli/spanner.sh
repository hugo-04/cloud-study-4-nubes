#!/usr/bin/env bash
# Spanner. Uso: ./spanner.sh <proyecto> <instancia> <base>
set -euo pipefail
P="${1:?proyecto}"; I="${2:?instancia}"; D="${3:?base}"
gcloud spanner instances describe "$I" --project "$P" --format='value(config,processingUnits)'
gcloud spanner databases ddl describe "$D" --instance "$I" --project "$P"
gcloud spanner databases execute-sql "$D" --instance "$I" --project "$P" --sql 'SELECT Sku, Stock FROM Inventario LIMIT 5'
