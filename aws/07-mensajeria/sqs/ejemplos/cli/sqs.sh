#!/usr/bin/env bash
# Comandos de ejemplo para SQS. Define COLA_URL y DLQ_ARN.
set -euo pipefail
COLA_URL="${COLA_URL:?define COLA_URL}"

# Enviar con atributos
aws sqs send-message --queue-url "$COLA_URL" \
  --message-body file://../json/mensaje-orden.json \
  --message-attributes '{"tipo":{"DataType":"String","StringValue":"OrdenCreada"},"correlacion":{"DataType":"String","StringValue":"ord-48213"}}'

# Enviar un lote de hasta 10
# aws sqs send-message-batch --queue-url "$COLA_URL" --entries file://lote.json

# Recibir con long polling y ver el número de recepciones
aws sqs receive-message --queue-url "$COLA_URL" --max-number-of-messages 5 --wait-time-seconds 20 \
  --attribute-names ApproximateReceiveCount --message-attribute-names All

# Estado de la cola
aws sqs get-queue-attributes --queue-url "$COLA_URL" --attribute-names \
  ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible ApproximateNumberOfMessagesDelayed RedrivePolicy

# Reprocesar la DLQ hacia la cola original (tras corregir el error)
# aws sqs start-message-move-task --source-arn "$DLQ_ARN"
# aws sqs list-message-move-tasks --source-arn "$DLQ_ARN"

# Vaciar una cola de pruebas (¡irreversible!)
# aws sqs purge-queue --queue-url "$COLA_URL"
