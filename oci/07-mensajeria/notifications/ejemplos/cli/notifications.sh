#!/usr/bin/env bash
# Notifications. Uso: ./notifications.sh <topic-ocid>
set -euo pipefail
T="${1:?topic ocid}"
C=$(oci ons topic get --topic-id "$T" --query 'data."compartment-id"' --raw-output)
echo "== Suscripciones del tema"
oci ons subscription list -c "$C" --topic-id "$T" --all --query 'data[].{protocolo:protocol,endpoint:endpoint,estado:"lifecycle-state"}' --output table
echo "== Publicar prueba"
oci ons message publish --topic-id "$T" --title "Prueba de alertas" --body "Mensaje de prueba $(date -u +%FT%TZ)"
