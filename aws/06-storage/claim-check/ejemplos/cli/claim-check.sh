#!/usr/bin/env bash
# Prueba manual del flujo Claim Check. Define BUCKET y COLA_URL.
set -euo pipefail
BUCKET="${BUCKET:?define BUCKET}"
COLA_URL="${COLA_URL:?define COLA_URL}"
ARCHIVO="${1:-./pedido.pdf}"

# 1) Hash y subida (el bucket debe tener versionado)
SHA=$(openssl dgst -sha256 -binary "$ARCHIVO" | base64)
CLAVE="cc/pedidos/$(date -u +%Y/%m/%d)/$(uuidgen)"
VERSION=$(aws s3api put-object --bucket "$BUCKET" --key "$CLAVE" --body "$ARCHIVO" \
  --checksum-sha256 "$SHA" --content-type application/pdf --query VersionId --output text)

# 2) Publicar el ticket DESPUÉS de subir
TICKET=$(cat <<JSON
{"version":1,"bucket":"$BUCKET","clave":"$CLAVE","versionId":"$VERSION","tamano":$(stat -c%s "$ARCHIVO"),"sha256":"$SHA","contentType":"application/pdf","correlacion":"prueba-$(date +%s)","creado":"$(date -u +%FT%TZ)"}
JSON
)
aws sqs send-message --queue-url "$COLA_URL" --message-body "$TICKET"

# 3) Ver la cola y la DLQ
aws sqs get-queue-attributes --queue-url "$COLA_URL" \
  --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible RedrivePolicy
