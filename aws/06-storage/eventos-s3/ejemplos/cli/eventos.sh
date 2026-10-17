#!/usr/bin/env bash
# Configurar y probar eventos de S3. Define BUCKET, COLA_ARN.
set -euo pipefail
BUCKET="${BUCKET:?define BUCKET}"
COLA_ARN="${COLA_ARN:?define COLA_ARN}"

cat > /tmp/notificacion.json <<JSON
{
  "QueueConfigurations": [{
    "Id": "csv-de-entrada",
    "QueueArn": "$COLA_ARN",
    "Events": ["s3:ObjectCreated:*"],
    "Filter": { "Key": { "FilterRules": [
      { "Name": "prefix", "Value": "entrada/" },
      { "Name": "suffix", "Value": ".csv" } ] } }
  }],
  "EventBridgeConfiguration": {}
}
JSON
# Falla si la política de la cola no autoriza a S3 (SourceArn + SourceAccount)
aws s3api put-bucket-notification-configuration --bucket "$BUCKET" \
  --notification-configuration file:///tmp/notificacion.json
aws s3api get-bucket-notification-configuration --bucket "$BUCKET"

# Probar: subir un archivo que cumpla el filtro y mirar la cola
echo "a,b" > /tmp/prueba.csv
aws s3 cp /tmp/prueba.csv "s3://$BUCKET/entrada/prueba.csv"
sleep 3
aws sqs receive-message --queue-url "$(aws sqs get-queue-url --queue-name "${COLA_ARN##*:}" --query QueueUrl --output text)" \
  --max-number-of-messages 5 --wait-time-seconds 10
