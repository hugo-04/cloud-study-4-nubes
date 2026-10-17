#!/usr/bin/env bash
# Operación diaria de la capa de eventos (ajusta ENT y la región).
ENT=prod

# 1. Publicar un evento de prueba
aws events put-events --entries file://../json/pedido-creado.json

# 2. ¿El patrón de logística coincide con el evento? (sin enviar nada)
aws events test-event-pattern \
  --event-pattern file://../json/patron-logistica.json \
  --event "$(jq -c '.[0]|{id:"1",version:"0",account:"111122223333",time:"2026-01-01T00:00:00Z",region:"us-east-1",resources:[],source:.Source,"detail-type":.DetailType,detail:(.Detail|fromjson)}' ../json/pedido-creado.json)"

# 3. Antigüedad del mensaje más viejo y DLQ de cada consumidor
for c in facturacion notificaciones logistica; do
  aws sqs get-queue-attributes --queue-url "$(aws sqs get-queue-url --queue-name $ENT-$c --query QueueUrl --output text)" \
    --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible
  aws sqs get-queue-attributes --queue-url "$(aws sqs get-queue-url --queue-name $ENT-$c-dlq --query QueueUrl --output text)" \
    --attribute-names ApproximateNumberOfMessages
done

# 4. Reproducir una ventana del archivo tras corregir un error del consumidor
aws events start-replay --replay-name "reproceso-$(date +%Y%m%d%H%M)" \
  --event-source-arn "arn:aws:events:us-east-1:111122223333:event-archive/$ENT-ordenes" \
  --destination "Arn=arn:aws:events:us-east-1:111122223333:event-bus/$ENT-ordenes" \
  --event-start-time 2026-01-01T10:00:00Z --event-end-time 2026-01-01T11:00:00Z

# 5. Devolver la DLQ a la cola (después de arreglar la causa)
aws sqs start-message-move-task --source-arn "arn:aws:sqs:us-east-1:111122223333:$ENT-facturacion-dlq"
