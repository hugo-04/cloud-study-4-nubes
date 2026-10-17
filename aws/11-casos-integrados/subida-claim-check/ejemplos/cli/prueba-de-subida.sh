#!/usr/bin/env bash
# Prueba manual del flujo (reemplaza URL y archivo). El Content-Type y el tamaño deben ser EXACTAMENTE los firmados.
set -euo pipefail
API=${API:-https://api.modalima.example}
ARCHIVO=${1:?uso: prueba-de-subida.sh archivo.pdf}
BYTES=$(stat -c %s "$ARCHIVO")

R=$(curl -sS -X POST "$API/cargas" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
     -d "{\"nombre\":\"$(basename "$ARCHIVO")\",\"tipo\":\"application/pdf\",\"bytes\":$BYTES}")
ID=$(echo "$R" | jq -r .idCarga); URL=$(echo "$R" | jq -r .urlSubida)

curl -sS -X PUT "$URL" -H 'Content-Type: application/pdf' --data-binary @"$ARCHIVO" -w '%{http_code}\n'

for i in 1 2 3 4 5 6; do
  E=$(curl -sS "$API/cargas/$ID" -H "Authorization: Bearer $TOKEN" | jq -r .estado); echo "estado: $E"
  [ "$E" = VALIDADO ] || [ "$E" = RECHAZADO ] && break; sleep 3
done

# Operación: ¿cuántas cargas hay por estado? ¿hay mensajes en la DLQ?
for e in PENDIENTE SUBIDO RECHAZADO; do
  echo -n "$e: "; aws dynamodb query --table-name prod-cargas --index-name por-estado \
    --key-condition-expression 'estado = :e' --expression-attribute-values "{\":e\":{\"S\":\"$e\"}}" --select COUNT --query Count --output text
done
aws sqs get-queue-attributes --queue-url "$(aws sqs get-queue-url --queue-name prod-validacion-dlq --query QueueUrl --output text)" \
  --attribute-names ApproximateNumberOfMessages --query Attributes.ApproximateNumberOfMessages --output text
