#!/usr/bin/env bash
# Events. Uso: ./events.sh <compartment-ocid>
set -euo pipefail
C="${1:?compartment}"
oci events rule list -c "$C" --all --query 'data[].{nombre:"display-name",activa:"is-enabled",id:id}' --output table
echo "== Condición de una regla:  oci events rule get --rule-id <id> --query 'data.condition' --raw-output | python3 -m json.tool"
