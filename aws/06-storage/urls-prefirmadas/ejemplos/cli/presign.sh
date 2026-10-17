#!/usr/bin/env bash
# Pruebas rápidas con URLs prefirmadas. Define BUCKET.
set -euo pipefail
BUCKET="${BUCKET:?define BUCKET}"

# GET prefirmado de 5 minutos (la CLI solo firma GET)
URL=$(aws s3 presign "s3://$BUCKET/uploads/ejemplo.txt" --expires-in 300)
echo "$URL" | sed 's/X-Amz-Signature=[0-9a-f]*/X-Amz-Signature=***/'   # no imprimas la firma real
curl -sS -o /dev/null -w "GET -> HTTP %{http_code}\n" "$URL"

# PUT: la URL la entrega tu backend; el cliente debe enviar EXACTAMENTE las cabeceras firmadas
# curl -X PUT "$URL_PUT" -H "Content-Type: image/png" --data-binary @foto.png

# CORS actual del bucket
aws s3api get-bucket-cors --bucket "$BUCKET"
aws s3api put-bucket-cors --bucket "$BUCKET" --cors-configuration file://../json/cors.json
