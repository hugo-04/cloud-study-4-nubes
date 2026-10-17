#!/usr/bin/env bash
# Autonomous Database. Uso: ./adb.sh <adb-ocid>
set -euo pipefail
A="${1:?adb ocid}"
oci db autonomous-database get --autonomous-database-id "$A" \
  --query 'data.{nombre:"display-name",estado:"lifecycle-state",ecpu:"compute-count",mtls:"is-mtls-connection-required",privado:"private-endpoint"}' --output table
echo "== Perfiles de conexión TLS one-way"
oci db autonomous-database get --autonomous-database-id "$A" \
  --query 'data."connection-strings".profiles[?"tls-authentication"==`SERVER`].{perfil:"display-name",grupo:"consumer-group"}' --output table
echo "== Clon de metadatos para pruebas:  oci db autonomous-database create-from-clone --clone-type METADATA ..."
