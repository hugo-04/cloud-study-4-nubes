#!/usr/bin/env bash
# Eventos de Blob por CLI: tópico del sistema, suscripciones, pruebas, métricas y dead-letter.
# Ejecuta por secciones. Requiere: az login (extensión eventgrid se instala sola si falta).
set -euo pipefail

RG=rg-estudio-eventos-blob
ST=stevXXXXXX                     # salida "cuenta" de Terraform
TOPICO=evgt-$ST
SB=sb-ev-XXXXXX                   # namespace de Service Bus
COLA=eventos-blob

ST_ID=$(az storage account show -g "$RG" -n "$ST" --query id -o tsv)
COLA_ID=$(az servicebus queue show -g "$RG" --namespace-name "$SB" -n "$COLA" --query id -o tsv)

echo "== 1) Tópico del sistema de la cuenta (uno por cuenta) con identidad administrada =="
az eventgrid system-topic create -g "$RG" -n "$TOPICO" --location eastus2 \
  --topic-type microsoft.storage.storageaccounts --source "$ST_ID" --identity systemassigned -o table

echo "== 2) Dar a la identidad del tópico permiso de ENVIAR a la cola =="
PRINCIPAL=$(az eventgrid system-topic show -g "$RG" -n "$TOPICO" --query identity.principalId -o tsv)
az role assignment create --assignee-object-id "$PRINCIPAL" --assignee-principal-type ServicePrincipal \
  --role "Azure Service Bus Data Sender" --scope "$COLA_ID" -o none

echo "== 3) Suscripción BlobCreated -> cola, CloudEvents, entrega con identidad, filtros =="
az eventgrid system-topic event-subscription create -g "$RG" --system-topic-name "$TOPICO" -n blobcreated-a-cola \
  --endpoint-type servicebusqueue --endpoint "$COLA_ID" \
  --delivery-identity-endpoint-type servicebusqueue --delivery-identity systemassigned --delivery-identity-endpoint "$COLA_ID" \
  --event-delivery-schema cloudeventschemav1_0 \
  --included-event-types Microsoft.Storage.BlobCreated \
  --subject-begins-with /blobServices/default/containers/subidas/blobs/entrada/ \
  --advanced-filter data.contentLength NumberGreaterThan 0 \
  --advanced-filter data.api StringIn PutBlob PutBlockList FlushWithClose SftpCommit \
  --max-delivery-attempts 30 --event-ttl 1440 -o table

echo "== 4) Listar y ver suscripciones =="
az eventgrid system-topic event-subscription list -g "$RG" --system-topic-name "$TOPICO" -o table
az eventgrid system-topic event-subscription show -g "$RG" --system-topic-name "$TOPICO" -n blobcreated-a-cola \
  --query '{estado:provisioningState,esquema:eventDeliverySchema,filtro:filter,reintentos:retryPolicy}' -o jsonc

echo "== 5) Probar: subir un archivo bajo entrada/ y ver el mensaje en la cola =="
echo 'sku,precio' > /tmp/prueba.csv
az storage blob upload --account-name "$ST" -c subidas -n "entrada/prueba-$(date +%s).csv" -f /tmp/prueba.csv --auth-mode login -o none
sleep 15
az servicebus queue show -g "$RG" --namespace-name "$SB" -n "$COLA" --query 'countDetails' -o jsonc

echo "== 6) Subir FUERA del prefijo: no debe llegar nada nuevo (Matched Events no cambia) =="
az storage blob upload --account-name "$ST" -c subidas -n "otra-ruta/prueba.csv" -f /tmp/prueba.csv --auth-mode login -o none

echo "== 7) Métricas del tópico: publicados, coincidentes, entregados, fallidos, dead-letter =="
az monitor metrics list --resource "$(az eventgrid system-topic show -g "$RG" -n "$TOPICO" --query id -o tsv)" \
  --metric PublishSuccessCount DeliverySuccessCount DeliveryAttemptFailCount DeadLetteredCount DroppedEventCount MatchedEventCount \
  --interval PT5M --aggregation Total -o table || true

echo "== 8) Enviar a mano un evento de ejemplo a tu webhook local (prueba del código Java) =="
# curl -sS -X POST "http://localhost:8080/eventos/blob?clave=$EVENTOS_CLAVE" -H 'Content-Type: application/json' \
#   -d @ejemplos/eventos/blobcreated-eventgrid.json -w '\nHTTP %{http_code}\n'
# curl -sS -X POST "http://localhost:8080/eventos/blob?clave=$EVENTOS_CLAVE" -H 'Content-Type: application/json' \
#   -d @ejemplos/eventos/validacion-eventgrid.json     # debe devolver {"validationResponse":"..."}
# curl -sS -X OPTIONS "http://localhost:8080/eventos/blob?clave=$EVENTOS_CLAVE" -H 'WebHook-Request-Origin: eventgrid.azure.net' -D -

echo "== 9) Dead-letter: listar lo que no se pudo entregar =="
az storage blob list --account-name "$ST" -c deadletter --auth-mode login --query '[].{nombre:name,tam:properties.contentLength,fecha:properties.lastModified}' -o table || true
# az storage blob download --account-name "$ST" -c deadletter -n <nombre> -f /tmp/dl.json --auth-mode login ; jq . /tmp/dl.json

echo "== 10) Actualizar el filtro sin recrear =="
az eventgrid system-topic event-subscription update -g "$RG" --system-topic-name "$TOPICO" -n blobcreated-a-cola \
  --subject-begins-with /blobServices/default/containers/subidas/blobs/entrada/ -o none

echo "== 11) Limpieza de la práctica =="
# az eventgrid system-topic event-subscription delete -g "$RG" --system-topic-name "$TOPICO" -n blobcreated-a-cola
# az group delete -n "$RG" --yes --no-wait
