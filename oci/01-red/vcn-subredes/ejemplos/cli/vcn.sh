#!/usr/bin/env bash
# Inspección de una VCN con la CLI de OCI. Uso: ./vcn.sh <compartment-ocid> <vcn-ocid>
set -euo pipefail
C="${1:?compartment ocid}"; V="${2:?vcn ocid}"
oci network vcn get --vcn-id "$V" --query 'data.{nombre:"display-name",cidrs:"cidr-blocks",dns:"dns-label"}' --output table
echo "== Subredes"
oci network subnet list -c "$C" --vcn-id "$V" --all \
  --query 'data[].{nombre:"display-name",cidr:"cidr-block",privada:"prohibit-public-ip-on-vnic"}' --output table
echo "== Tablas de rutas"
oci network route-table list -c "$C" --vcn-id "$V" --all \
  --query 'data[].{nombre:"display-name",reglas:"route-rules"[].{destino:destination,salto:"network-entity-id"}}' --output json
echo "== Gateways"
oci network internet-gateway list -c "$C" --vcn-id "$V" --query 'data[].{igw:"display-name"}' --output table
oci network nat-gateway list -c "$C" --vcn-id "$V" --query 'data[].{nat:"display-name",ip:"nat-ip"}' --output table
oci network service-gateway list -c "$C" --vcn-id "$V" --query 'data[].{sgw:"display-name"}' --output table
