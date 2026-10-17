#!/usr/bin/env bash
# Prueba efímera de workload identity. Uso: ./probar.sh
set -euo pipefail
kubectl -n tienda run prueba-oci --rm -it --restart=Never \
  --overrides='{"spec":{"serviceAccountName":"app-tienda"}}' \
  --image=ghcr.io/oracle/oci-cli:latest -- \
  oci os ns get --auth oke_workload_identity
