#!/usr/bin/env bash
# Operación de Functions con la CLI de OCI y la CLI fn. Uso: ./funciones.sh <compartment-ocid>
set -euo pipefail
C="${1:?compartment ocid}"
echo "== Aplicaciones"
oci fn application list -c "$C" --all --query 'data[].{nombre:"display-name",id:id}' --output table
echo "== Desplegar con fn (desde la carpeta de la función):  fn -v deploy --app tienda-funciones"
echo "== Invocar:  echo 'P-100|25.50|pen' | fn invoke tienda-funciones normalizador-pedido"
