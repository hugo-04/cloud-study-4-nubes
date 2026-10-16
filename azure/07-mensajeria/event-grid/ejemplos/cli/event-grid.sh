#!/usr/bin/env bash
# Event Grid por CLI: tópicos, suscripciones con filtros, publicar, namespaces (pull), métricas y dead-letter.
# Ejecuta por secciones. Requiere: az login (la extensión 'eventgrid' se instala sola).
set -euo pipefail

RG=rg-estudio-eventgrid
TOPICO=evgt-pedidos-XXXXXX              # salida del Terraform
SB_NS=sb-eg-XXXXXX
COLA=pedidos-eventos
LOC=eastus2

TOPICO_ID=$(az eventgrid topic show -g "$RG" -n "$TOPICO" --query id -o tsv)
COLA_ID=$(az servicebus queue show -g "$RG" --namespace-name "$SB_NS" -n "$COLA" --query id -o tsv)
ENDPOINT=$(az eventgrid topic show -g "$RG" -n "$TOPICO" --query endpoint -o tsv)

echo "== 1) Crear un tópico personalizado en CloudEvents, con identidad y sin claves =="
# az eventgrid topic create -g "$RG" -n "$TOPICO" -l "$LOC" --input-schema cloudeventschemav1_0 \
#   --identity systemassigned --public-network-access enabled --disable-local-auth true

echo "== 2) Suscripción a Service Bus con filtros, identidad de entrega y reintentos =="
az eventgrid event-subscription create --name pedidos-pagados-peru --source-resource-id "$TOPICO_ID" \
  --endpoint-type servicebusqueue --endpoint "$COLA_ID" \
  --event-delivery-schema cloudeventschemav1_0 \
  --included-event-types pe.modalima.pedido.creado pe.modalima.pedido.pagado \
  --subject-begins-with pedidos/PE/ \
  --advanced-filter data.total NumberGreaterThan 100 \
  --delivery-identity-endpoint-type servicebusqueue --delivery-identity systemassigned --delivery-identity-endpoint "$COLA_ID" \
  --max-delivery-attempts 30 --event-ttl 1440 -o table

echo "== 3) Listar y ver suscripciones del tópico =="
az eventgrid event-subscription list --source-resource-id "$TOPICO_ID" -o table
az eventgrid event-subscription show --name pedidos-pagados-peru --source-resource-id "$TOPICO_ID" \
  --query '{estado:provisioningState,esquema:eventDeliverySchema,filtro:filter,reintentos:retryPolicy}' -o jsonc

echo "== 4) Publicar un evento CloudEvents con tu token de Entra ID (rol EventGrid Data Sender) =="
TOKEN=$(az account get-access-token --resource https://eventgrid.azure.net --query accessToken -o tsv)
curl -sS -X POST "$ENDPOINT" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/cloudevents+json; charset=utf-8" \
  -d '{"specversion":"1.0","id":"evt-'"$(date +%s)"'","source":"/servicios/pedidos","type":"pe.modalima.pedido.creado","subject":"pedidos/PE/1001","time":"'"$(date -u +%FT%TZ)"'","datacontenttype":"application/json","data":{"pedidoId":"1001","clienteId":"u-42","region":"PE","total":150.0}}' \
  -w "publicar: HTTP %{http_code}\n"

echo "== 5) Un evento que NO pasa el filtro (total <= 100): no debe llegar a la cola =="
curl -sS -X POST "$ENDPOINT" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/cloudevents+json; charset=utf-8" \
  -d '{"specversion":"1.0","id":"evt-bajo-'"$(date +%s)"'","source":"/servicios/pedidos","type":"pe.modalima.pedido.creado","subject":"pedidos/PE/1002","datacontenttype":"application/json","data":{"pedidoId":"1002","region":"PE","total":20.0}}' \
  -w "publicar (filtrado): HTTP %{http_code}\n"
sleep 10
az servicebus queue show -g "$RG" --namespace-name "$SB_NS" -n "$COLA" --query countDetails -o jsonc

echo "== 6) Métricas del tópico: publicados, coincidentes, entregados, fallidos, dead-letter =="
az monitor metrics list --resource "$TOPICO_ID" \
  --metric PublishSuccessCount MatchedEventCount DeliverySuccessCount DeliveryAttemptFailCount DeadLetteredCount DroppedEventCount \
  --interval PT5M --aggregation Total -o table || true

echo "== 7) Dominio: crear un tópico hijo y publicar para ese cliente (source = nombre del tópico hijo) =="
# az eventgrid domain topic create -g "$RG" --domain-name <dominio> -n cliente-nuevo
# curl -X POST "<endpoint-del-dominio>" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/cloudevents+json" \
#   -d '{"specversion":"1.0","id":"1","source":"cliente-nuevo","type":"pe.modalima.factura.emitida","subject":"facturas/1","data":{"facturaId":"1"}}'

echo "== 8) Tópico del sistema de Key Vault y su suscripción a la cola =="
# az eventgrid system-topic create -g "$RG" -n evgt-kv --topic-type microsoft.keyvault.vaults --source <id-del-key-vault> -l "$LOC" --identity systemassigned
# az eventgrid system-topic event-subscription create -g "$RG" --system-topic-name evgt-kv -n secretos-por-vencer \
#   --endpoint-type servicebusqueue --endpoint <id-cola-kv> --included-event-types Microsoft.KeyVault.SecretNearExpiry Microsoft.KeyVault.SecretExpired \
#   --delivery-identity-endpoint-type servicebusqueue --delivery-identity systemassigned --delivery-identity-endpoint <id-cola-kv>

echo "== 9) Espacio de nombres: crear una suscripción PULL (la CLI de eventgrid puede requerir la extensión más reciente) =="
# az eventgrid namespace topic event-subscription create -g "$RG" --namespace-name <ns> --topic-name pedidos -n consumidores \
#   --delivery-configuration "{deliveryMode:Queue,queue:{receiveLockDurationInSeconds:60,maxDeliveryCount:10,eventTimeToLive:P1D}}"

echo "== 10) Dead-letter: ver lo que no se pudo entregar =="
# az storage blob list --account-name <cuenta> -c deadletter-eventos --auth-mode login -o table

echo "== 11) Probar el webhook local con eventos de ejemplo =="
# curl -X POST "http://localhost:8080/eventos/pedidos" -H 'Content-Type: application/cloudevents+json' -d @eventos/pedido-creado.json

echo "== 12) Limpieza =="
# az eventgrid event-subscription delete --name pedidos-pagados-peru --source-resource-id "$TOPICO_ID"
