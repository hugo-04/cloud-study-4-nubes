#!/usr/bin/env bash
# NoSQL. Uso: ./nosql.sh <compartment-ocid> <tabla>
set -euo pipefail
C="${1:?compartment}"; T="${2:?tabla}"
oci nosql table get --table-name-or-id "$T" -c "$C" --query 'data.{estado:"lifecycle-state",limites:"table-limits"}'
oci nosql row update --table-name-or-id "$T" -c "$C" --value '{"id_cliente":"C-1","id_carrito":"actual","items":[],"total":0}' --ttl 7
oci nosql row get --table-name-or-id "$T" -c "$C" --key '["id_cliente:C-1","id_carrito:actual"]'
