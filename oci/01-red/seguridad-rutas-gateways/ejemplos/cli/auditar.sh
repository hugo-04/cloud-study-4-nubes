#!/usr/bin/env bash
# Reglas de entrada abiertas a todo Internet en listas de seguridad y NSG. Uso: ./auditar.sh <compartment-ocid> <vcn-ocid>
set -euo pipefail
C="${1:?compartment}"; V="${2:?vcn}"
echo "== Listas de seguridad con entrada desde 0.0.0.0/0"
oci network security-list list -c "$C" --vcn-id "$V" --all \
  --query "data[?\"ingress-security-rules\"[?source=='0.0.0.0/0']].{lista:\"display-name\",reglas:\"ingress-security-rules\"[?source=='0.0.0.0/0'].{proto:protocol,tcp:\"tcp-options\".\"destination-port-range\"}}" --output json
echo "== NSG y sus reglas abiertas"
for nsg in $(oci network nsg list -c "$C" --vcn-id "$V" --all --query 'data[].id' --raw-output | tr -d '[]," '); do
  oci network nsg rules list --nsg-id "$nsg" --all \
    --query "data[?direction=='INGRESS' && source=='0.0.0.0/0'].{nsg:'$nsg',proto:protocol,tcp:\"tcp-options\".\"destination-port-range\"}" --output json
done
