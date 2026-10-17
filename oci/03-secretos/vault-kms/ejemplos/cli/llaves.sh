#!/usr/bin/env bash
# Operación de llaves con la CLI de OCI. Uso: ./llaves.sh <compartment-ocid> <management-endpoint>
set -euo pipefail
C="${1:?compartment ocid}"
M="${2:?management endpoint (https://...-management.kms.<region>.oraclecloud.com)}"
echo "== Vaults"
oci kms management vault list -c "$C" --all --query 'data[].{nombre:"display-name",tipo:"vault-type",estado:"lifecycle-state"}' --output table
echo "== Llaves"
oci kms management key list -c "$C" --endpoint "$M" --all --query 'data[].{nombre:"display-name",estado:"lifecycle-state",proteccion:"protection-mode"}' --output table
echo "== Programar rotación (nueva versión) de una llave:  oci kms management key create-key-version --key-id <ocid> --endpoint \$M"
echo "== Programar borrado (ventana 30 días):  oci kms management key schedule-deletion --key-id <ocid> --time-of-deletion <fecha> --endpoint \$M"
