#!/usr/bin/env bash
# Prueba. Uso: ./subida.sh <url_subidas> <archivo.pdf>
set -euo pipefail
U="${1:?url}"; F="${2:?archivo}"
TOKEN=$(gcloud auth print-identity-token)
FIRMADA=$(curl -fsS -X POST "$U/subidas" -H "Authorization: Bearer $TOKEN" | sed -E 's/.*"url":"([^"]+)".*/\1/')
curl -fsS -X PUT -H 'Content-Type: application/pdf' --upload-file "$F" "$FIRMADA"
gcloud storage ls gs://modalima-subidas/aprobados/ | tail -3
