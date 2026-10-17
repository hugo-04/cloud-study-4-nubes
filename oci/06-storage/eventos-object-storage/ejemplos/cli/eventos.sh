#!/usr/bin/env bash
# Eventos de Object Storage. Uso: ./eventos.sh <compartment-ocid> <bucket>
set -euo pipefail
C="${1:?compartment}"; B="${2:?bucket}"
echo "== ¿Eventos activos en el bucket?"
oci os bucket get -bn "$B" --query 'data."object-events-enabled"'
echo "== Reglas"
oci events rule list -c "$C" --all --query 'data[].{nombre:"display-name",activa:"is-enabled",estado:"lifecycle-state"}' --output table
echo "== Disparar un evento de prueba"
echo "hola" > /tmp/prueba-evento.txt
oci os object put -bn "$B" --file /tmp/prueba-evento.txt --name "fotos/prueba-$(date +%s).txt" --force
