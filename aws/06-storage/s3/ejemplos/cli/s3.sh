#!/usr/bin/env bash
# Comandos de ejemplo para S3. Define BUCKET antes de ejecutar.
set -euo pipefail
BUCKET="${BUCKET:?define BUCKET}"

# Estado de seguridad del bucket
aws s3api get-public-access-block --bucket "$BUCKET"
aws s3api get-bucket-encryption   --bucket "$BUCKET"
aws s3api get-bucket-versioning   --bucket "$BUCKET"

# Subir con checksum SHA-256 y cifrado KMS (multiparte automática en archivos grandes)
aws s3 cp ./factura.pdf "s3://$BUCKET/facturas/2026/10/16/f-001.pdf" \
  --sse aws:kms --checksum-algorithm SHA256

# Escritura condicional: solo si NO existe (falla con 412 si ya existe)
aws s3api put-object --bucket "$BUCKET" --key reportes/diario-2026-10-16.csv \
  --body ./reporte.csv --if-none-match '*'

# Listar un prefijo y ver metadatos
aws s3api list-objects-v2 --bucket "$BUCKET" --prefix facturas/2026/10/ --max-items 20
aws s3api head-object --bucket "$BUCKET" --key facturas/2026/10/16/f-001.pdf --checksum-mode ENABLED

# Versiones y recuperación de un borrado accidental (quitar el marcador de borrado)
aws s3api list-object-versions --bucket "$BUCKET" --prefix facturas/2026/10/16/f-001.pdf
# aws s3api delete-object --bucket "$BUCKET" --key facturas/2026/10/16/f-001.pdf --version-id <ID_DEL_MARCADOR>

# Ciclo de vida desde JSON
aws s3api put-bucket-lifecycle-configuration --bucket "$BUCKET" \
  --lifecycle-configuration file://../json/lifecycle.json

# Cargas multiparte incompletas pendientes
aws s3api list-multipart-uploads --bucket "$BUCKET"
