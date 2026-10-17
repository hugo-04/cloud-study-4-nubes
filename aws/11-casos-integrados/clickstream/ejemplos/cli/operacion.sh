#!/usr/bin/env bash
# Operación diaria del stream de clics.
STREAM=prod-clics

# 1. ¿Cuántos shards/modo tiene y cuánta retención?
aws kinesis describe-stream-summary --stream-name $STREAM \
  --query 'StreamDescriptionSummary.{modo:StreamModeDetails.StreamMode,shards:OpenShardCount,retencionH:RetentionPeriodHours}'

# 2. ¿Va atrasado el consumidor? (milisegundos que el lector está detrás del último dato)
aws cloudwatch get-metric-statistics --namespace AWS/Kinesis --metric-name GetRecords.IteratorAgeMilliseconds \
  --dimensions Name=StreamName,Value=$STREAM --start-time "$(date -u -d '-15 min' +%FT%TZ)" --end-time "$(date -u +%FT%TZ)" \
  --period 60 --statistics Maximum --query 'Datapoints[].Maximum'

# 3. ¿Se está estrangulando la escritura? (distribución desigual = clave caliente)
aws cloudwatch get-metric-statistics --namespace AWS/Kinesis --metric-name WriteProvisionedThroughputExceeded \
  --dimensions Name=StreamName,Value=$STREAM --start-time "$(date -u -d '-15 min' +%FT%TZ)" --end-time "$(date -u +%FT%TZ)" \
  --period 60 --statistics Sum --query 'Datapoints[].Sum'

# 4. Mirar unos registros reales de un shard (diagnóstico; no es para producción)
SHARD=$(aws kinesis list-shards --stream-name $STREAM --query 'Shards[0].ShardId' --output text)
IT=$(aws kinesis get-shard-iterator --stream-name $STREAM --shard-id "$SHARD" --shard-iterator-type TRIM_HORIZON --query ShardIterator --output text)
aws kinesis get-records --shard-iterator "$IT" --limit 3 --query 'Records[].[SequenceNumber,PartitionKey]'

# 5. Cambiar de modo con criterio (solo si la carga se volvió estable y medida)
# aws kinesis update-stream-mode --stream-arn <arn> --stream-mode-details StreamMode=PROVISIONED
