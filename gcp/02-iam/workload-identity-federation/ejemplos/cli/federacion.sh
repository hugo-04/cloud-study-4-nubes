#!/usr/bin/env bash
# Genera el archivo de configuración (sin secretos) para el pipeline. Uso: ./federacion.sh <numero-proyecto> <pool> <proveedor> [cuenta-a-suplantar]
set -euo pipefail
N="${1:?numero}"; POOL="${2:?pool}"; PROV="${3:?proveedor}"
ARGS=(--output-file=cred-federada.json --credential-source-file=/tmp/token-oidc.jwt)
[ -n "${4:-}" ] && ARGS+=(--service-account="$4")
gcloud iam workload-identity-pools create-cred-config "projects/$N/locations/global/workloadIdentityPools/$POOL/providers/$PROV" "${ARGS[@]}"
echo "En el pipeline: escribe el token OIDC en /tmp/token-oidc.jwt y exporta GOOGLE_APPLICATION_CREDENTIALS=cred-federada.json"
