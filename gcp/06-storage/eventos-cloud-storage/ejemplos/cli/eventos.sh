#!/usr/bin/env bash
# Eventos de Cloud Storage. Uso: ./eventos.sh <bucket>
set -euo pipefail
B="${1:?bucket}"
gcloud storage buckets notifications list "gs://$B"
echo hola > /tmp/prueba.txt
gcloud storage cp /tmp/prueba.txt "gs://$B/fotos/prueba-$(date +%s).txt"
