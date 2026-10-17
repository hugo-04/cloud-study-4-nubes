#!/usr/bin/env bash
# Diagnóstico de federación. Uso: ./autenticacion.sh <proyecto> <pool> <proveedor>
set -euo pipefail
P="${1:?proyecto}"; POOL="${2:?pool}"; PROV="${3:?proveedor}"
gcloud iam workload-identity-pools providers describe "$PROV" --workload-identity-pool "$POOL" --location global --project "$P" \
  --format='yaml(attributeMapping,attributeCondition,oidc)'
gcloud auth list
gcloud config get account
