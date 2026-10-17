#!/usr/bin/env bash
# Comandos de ejemplo para Kinesis Data Streams. Define STREAM (nombre).
set -euo pipefail
STREAM="${STREAM:?define STREAM}"

# Crear en modo bajo demanda (o aprovisionado: --shard-count 2)
# aws kinesis create-stream --stream-name "$STREAM" --stream-mode-details StreamMode=ON_DEMAND

# Escribir un registro (la clave decide el shard)
aws kinesis put-record --stream-name "$STREAM" --partition-key usuario-42 \
  --cli-binary-format raw-in-base64-out --data '{"tipo":"vista","sku":"A1","sesion":"s-901"}'

# Escribir un lote (Data en base64 dentro del archivo)
aws kinesis put-records --cli-input-json file://../json/registros-putrecords.json
# → revisa "FailedRecordCount" y los "ErrorCode" por registro

# Ver shards y rangos de hash
aws kinesis list-shards --stream-name "$STREAM"
aws kinesis describe-stream-summary --stream-name "$STREAM"

# Leer a mano (solo diagnóstico): iterador desde lo más antiguo
SHARD="$(aws kinesis list-shards --stream-name "$STREAM" --query 'Shards[0].ShardId' --output text)"
IT="$(aws kinesis get-shard-iterator --stream-name "$STREAM" --shard-id "$SHARD" \
  --shard-iterator-type TRIM_HORIZON --query ShardIterator --output text)"
aws kinesis get-records --shard-iterator "$IT" --limit 10

# Ampliar retención antes de que un lector atrasado pierda datos
# aws kinesis increase-stream-retention-period --stream-name "$STREAM" --retention-period-hours 72

# Aprovisionado: duplicar shards
# aws kinesis update-shard-count --stream-name "$STREAM" --target-shard-count 4 --scaling-type UNIFORM_SCALING

# Fan-out mejorado: registrar un consumidor
# aws kinesis register-stream-consumer --stream-arn "$(aws kinesis describe-stream-summary --stream-name "$STREAM" --query StreamDescriptionSummary.StreamARN --output text)" --consumer-name antifraude

# Atraso de lectura (últimos 30 min)
aws cloudwatch get-metric-statistics --namespace AWS/Kinesis --metric-name GetRecords.IteratorAgeMilliseconds \
  --dimensions Name=StreamName,Value="$STREAM" --start-time "$(date -u -d '-30 minutes' +%FT%TZ)" \
  --end-time "$(date -u +%FT%TZ)" --period 60 --statistics Maximum
