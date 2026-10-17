#!/usr/bin/env bash
# Grupos dinámicos y pruebas de principal. Uso: ./grupos.sh <tenancy-ocid>
set -euo pipefail
T="${1:?tenancy ocid}"
echo "== Grupos dinámicos y sus reglas"
oci iam dynamic-group list -c "$T" --all --query 'data[].{nombre:name,regla:"matching-rule"}' --output table
echo "== Dentro de la VM: ¿llego a los metadatos?"
echo 'curl -s -H "Authorization: Bearer Oracle" http://169.254.169.254/opc/v2/instance/id'
echo "== Dentro de la VM: probar la CLI como instance principal"
echo 'oci os ns get --auth instance_principal'
