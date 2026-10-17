#!/usr/bin/env bash
# Operación de instancias con la CLI de OCI. Uso: ./instancias.sh <compartment-ocid>
set -euo pipefail
C="${1:?compartment ocid}"
echo "== Instancias"
oci compute instance list -c "$C" --all --query 'data[].{nombre:"display-name",estado:"lifecycle-state",forma:shape,horario:"freeform-tags".horario}' --output table
echo "== Apagar (suave) una instancia:  oci compute instance action --instance-id <ocid> --action SOFTSTOP"
echo "== Encender:                      oci compute instance action --instance-id <ocid> --action START"
