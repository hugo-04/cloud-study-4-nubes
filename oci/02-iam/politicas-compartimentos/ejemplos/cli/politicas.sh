#!/usr/bin/env bash
# Operación de políticas con la CLI de OCI. Uso: ./politicas.sh <compartment-ocid>
set -euo pipefail
C="${1:?compartment ocid}"
echo "== Políticas del compartimento"
oci iam policy list -c "$C" --all --query 'data[].{nombre:name,frases:length(statements)}' --output table
echo "== Frases con any-user o all-resources (revisar)"
oci iam policy list -c "$C" --all --query "data[].{nombre:name,frases:statements[?contains(@,'any-user') || contains(@,'all-resources')]}" --output json
echo "== Grupos dinámicos"
oci iam dynamic-group list --all --query 'data[].{nombre:name,regla:"matching-rule"}' --output table
