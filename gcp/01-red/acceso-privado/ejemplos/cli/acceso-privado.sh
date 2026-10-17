#!/usr/bin/env bash
# Pruebas desde una VM privada. Uso: ./acceso-privado.sh
set -uo pipefail
for n in storage.googleapis.com secretmanager.googleapis.com; do
  echo "== $n"; getent hosts "$n" || echo "no resuelve"
  curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 "https://$n/" || echo "sin ruta"
done
echo "== Conexiones PSA:  gcloud services vpc-peerings list --network=<red>"
