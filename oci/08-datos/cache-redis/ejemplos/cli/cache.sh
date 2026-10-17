#!/usr/bin/env bash
# OCI Cache. Uso: ./cache.sh <cluster-ocid> [usuario]
set -euo pipefail
R="${1:?cluster ocid}"
H=$(oci redis redis-cluster get --redis-cluster-id "$R" --query 'data."primary-fqdn"' --raw-output)
oci redis redis-cluster get --redis-cluster-id "$R" --query 'data.{estado:"lifecycle-state",nodos:"node-count",gb:"node-memory-in-gbs",version:"software-version",modo:"cluster-mode"}' --output table
echo "== Prueba (desde una VM en la VCN):  redis-cli --tls -h $H -p 6379 ${2:+--user $2 --askpass} PING"
