#!/usr/bin/env bash
# Verificación posterior de una unidad. Uso: ./verificar.sh <tenancy-ocid> <nombre-unidad>
set -uo pipefail
T="${1:?tenancy}"; U="${2:?unidad}"; fallos=0
chk() { if eval "$2" >/dev/null 2>&1; then echo "OK    $1"; else echo "FALLA $1 (o no se pudo comprobar)"; fallos=$((fallos+1)); fi; }
UID_=$(oci iam compartment list -c "$T" --name "$U" --query 'data[0].id' --raw-output 2>/dev/null)
chk "compartimento $U" "[ -n '$UID_' ] && [ '$UID_' != 'null' ]"
for e in prod no-prod; do
  chk "compartimento $U/$e" "oci iam compartment list -c '$UID_' --name $e --query 'data[0].id' --raw-output | grep -q ocid1"
done
chk "grupo $U-admins" "oci iam group list -c '$T' --name $U-admins --query 'data[0].id' --raw-output | grep -q ocid1"
chk "presupuesto de $U" "oci budgets budget list -c '$T' --all --query \"data[?contains(\\\"display-name\\\",'$U')].id\" --raw-output | grep -q ocid1"
echo "fallos: $fallos"; exit $fallos
