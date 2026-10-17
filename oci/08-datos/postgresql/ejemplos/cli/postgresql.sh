#!/usr/bin/env bash
# PostgreSQL. Uso: ./postgresql.sh <db-system-ocid>
set -euo pipefail
D="${1:?db system ocid}"
oci psql db-system get --db-system-id "$D" \
  --query 'data.{nombre:"display-name",estado:"lifecycle-state",version:"db-version",nodos:"instance-count",ip:"network-details"."primary-db-endpoint-private-ip"}' --output table
echo "== Conexión de prueba:  psql \"host=<ip> port=5432 dbname=postgres user=app_pedidos sslmode=verify-full sslrootcert=raiz.pem\""
