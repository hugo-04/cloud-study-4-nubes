#!/usr/bin/env bash
# Cloud KMS. Uso: ./kms.sh <proyecto> <ubicacion> <llavero> <llave>
set -euo pipefail
P="${1:?proyecto}"; L="${2:?ubicacion}"; R="${3:?llavero}"; K="${4:?llave}"
gcloud kms keys describe "$K" --keyring "$R" --location "$L" --project "$P" --format='yaml(purpose,primary.name,rotationPeriod,versionTemplate)'
gcloud kms keys versions list --key "$K" --keyring "$R" --location "$L" --project "$P" --format='table(name.basename(),state,protectionLevel)'
echo -n "hola" | gcloud kms encrypt --key "$K" --keyring "$R" --location "$L" --project "$P" --plaintext-file=- --ciphertext-file=/tmp/c.bin
gcloud kms decrypt --key "$K" --keyring "$R" --location "$L" --project "$P" --ciphertext-file=/tmp/c.bin --plaintext-file=-; echo
