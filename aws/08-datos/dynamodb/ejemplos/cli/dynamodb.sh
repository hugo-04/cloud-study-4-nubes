#!/usr/bin/env bash
# Comandos de ejemplo para DynamoDB. Define TABLE (p. ej. prod-pedidos).
set -euo pipefail
TABLE="${TABLE:?define TABLE}"

# Crear la tabla desde el JSON de ejemplo (equivale al Terraform)
# aws dynamodb create-table --cli-input-json file://../json/tabla-pedidos.json

# Escribir un ítem solo si no existe (idempotencia / creación única)
aws dynamodb put-item --table-name "$TABLE" --item file://../json/item-orden.json \
  --condition-expression "attribute_not_exists(pk)"

# Query por clave de partición y prefijo de ordenación, recientes primero
aws dynamodb query --table-name "$TABLE" \
  --key-condition-expression "pk = :p AND begins_with(sk, :o)" \
  --expression-attribute-values '{":p":{"S":"CLIENTE#42"},":o":{"S":"ORDEN#"}}' \
  --no-scan-index-forward --limit 20

# Consultar el índice (sin olvidar el nombre)
aws dynamodb query --table-name "$TABLE" --index-name gsi1 \
  --key-condition-expression "gsi1pk = :e" \
  --expression-attribute-values '{":e":{"S":"ESTADO#PAGADO"}}'

# Actualización atómica con condición (descontar stock sin carrera)
# aws dynamodb update-item --table-name "$TABLE" --key '{"pk":{"S":"SKU#A1"},"sk":{"S":"STOCK"}}' \
#   --update-expression "SET cantidad = cantidad - :n" --condition-expression "cantidad >= :n" \
#   --expression-attribute-values '{":n":{"N":"2"}}'

# Bloqueo optimista con versión
# aws dynamodb update-item --table-name "$TABLE" --key '{"pk":{"S":"CLIENTE#42"},"sk":{"S":"PERFIL"}}' \
#   --update-expression "SET nombre = :n, version = :nueva" --condition-expression "version = :actual" \
#   --expression-attribute-values '{":n":{"S":"Ana"},":nueva":{"N":"4"},":actual":{"N":"3"}}'

# Activar TTL y PITR
# aws dynamodb update-time-to-live --table-name prod-idempotencia --time-to-live-specification Enabled=true,AttributeName=expira_en
# aws dynamodb update-continuous-backups --table-name "$TABLE" --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true

# Diagnóstico: tamaño aproximado, índices y capacidad
aws dynamodb describe-table --table-name "$TABLE" --query 'Table.{Estado:TableStatus,Items:ItemCount,Bytes:TableSizeBytes,Modo:BillingModeSummary.BillingMode,Indices:GlobalSecondaryIndexes[].IndexName}'

# Restaurar a un punto en el tiempo (crea OTRA tabla)
# aws dynamodb restore-table-to-point-in-time --source-table-name "$TABLE" --target-table-name "$TABLE-restaurada" --use-latest-restorable-time
