#!/usr/bin/env bash
# Service Bus por CLI: entidades, reglas, mensajes de prueba, métricas y DLQ.
# Ejecuta por secciones. Requiere: az login y rol adecuado (Contributor para crear; Data Sender/Receiver para mensajes).
set -euo pipefail

RG=rg-estudio-servicebus
SB=sb-modalima-XXXXXX              # salida "namespace" de Terraform (sin .servicebus.windows.net)
LOC=eastus2

echo "== 1) Namespace sin claves (solo Entra ID) =="
# az servicebus namespace create -g "$RG" -n "$SB" -l "$LOC" --sku Standard --min-tls-version 1.2 --disable-local-auth true
az servicebus namespace show -g "$RG" -n "$SB" \
  --query '{sku:sku.name,sinClaves:disableLocalAuth,tls:minimumTlsVersion,publico:publicNetworkAccess,estado:status}' -o table

echo "== 2) Cola con duplicados, DLQ por expiración y entregas máximas =="
az servicebus queue create -g "$RG" --namespace-name "$SB" -n pedidos-demo \
  --lock-duration PT1M --max-delivery-count 8 --default-message-time-to-live P14D \
  --enable-dead-lettering-on-message-expiration true \
  --enable-duplicate-detection true --duplicate-detection-history-time-window PT10M -o none

echo "== 3) Tópico, suscripción con filtro de correlación y otra con filtro SQL =="
az servicebus topic create -g "$RG" --namespace-name "$SB" -n eventos-demo -o none
az servicebus topic subscription create -g "$RG" --namespace-name "$SB" --topic-name eventos-demo -n facturacion --max-delivery-count 8 -o none
az servicebus topic subscription rule delete -g "$RG" --namespace-name "$SB" --topic-name eventos-demo --subscription-name facturacion -n '$Default' -o none
az servicebus topic subscription rule create -g "$RG" --namespace-name "$SB" --topic-name eventos-demo --subscription-name facturacion \
  -n solo-pagados --filter-type CorrelationFilter --label pedido.pagado -o none
az servicebus topic subscription create -g "$RG" --namespace-name "$SB" --topic-name eventos-demo -n inventario -o none
az servicebus topic subscription rule delete -g "$RG" --namespace-name "$SB" --topic-name eventos-demo --subscription-name inventario -n '$Default' -o none
az servicebus topic subscription rule create -g "$RG" --namespace-name "$SB" --topic-name eventos-demo --subscription-name inventario \
  -n peru-grande --filter-sql-expression "region = 'PE' AND total > 100" -o none

echo "== 4) Listar entidades y reglas =="
az servicebus queue list -g "$RG" --namespace-name "$SB" --query '[].{cola:name,activos:countDetails.activeMessageCount,dlq:countDetails.deadLetterMessageCount}' -o table
az servicebus topic subscription list -g "$RG" --namespace-name "$SB" --topic-name eventos-demo --query '[].{suscripcion:name,activos:countDetails.activeMessageCount,dlq:countDetails.deadLetterMessageCount}' -o table
az servicebus topic subscription rule list -g "$RG" --namespace-name "$SB" --topic-name eventos-demo --subscription-name facturacion -o table

echo "== 5) Enviar un mensaje de prueba por REST con tu token de Entra ID (rol Data Sender) =="
TOKEN=$(az account get-access-token --resource https://servicebus.azure.net --query accessToken -o tsv)
curl -sS -X POST "https://${SB}.servicebus.windows.net/pedidos-demo/messages" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -H 'BrokerProperties: {"MessageId":"pedido-1001","Label":"pedido.crear","CorrelationId":"c-1"}' \
  -d '{"pedidoId":"1001","clienteId":"u-42","total":150.0,"region":"PE"}' -w "enviar: HTTP %{http_code}\n"

echo "== 6) El MISMO MessageId otra vez: lo descarta la detección de duplicados (HTTP 201 pero NO se encola) =="
curl -sS -X POST "https://${SB}.servicebus.windows.net/pedidos-demo/messages" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -H 'BrokerProperties: {"MessageId":"pedido-1001"}' -d '{"pedidoId":"1001"}' -w "duplicado: HTTP %{http_code}\n"

echo "== 7) Evento al tópico con propiedades de filtro =="
curl -sS -X POST "https://${SB}.servicebus.windows.net/eventos-demo/messages" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -H 'BrokerProperties: {"MessageId":"evt-1","Label":"pedido.pagado"}' -H 'region: PE' -H 'total: 150' \
  -d '{"pedidoId":"1001"}' -w "evento: HTTP %{http_code}\n"

echo "== 8) Ver sin consumir (peek) del primer mensaje: POST .../messages/head es receive-lock; para mirar usa Service Bus Explorer del portal =="
echo "En el portal: Namespace > Entidad > Service Bus Explorer > Peek from start (rol Data Receiver)."

echo "== 9) Mensajes en DLQ y su motivo (conteo por entidad) =="
az servicebus queue show -g "$RG" --namespace-name "$SB" -n pedidos-demo --query 'countDetails' -o jsonc

echo "== 10) Métricas útiles =="
az monitor metrics list --resource "$(az servicebus namespace show -g "$RG" -n "$SB" --query id -o tsv)" \
  --metric ActiveMessages DeadletteredMessages IncomingMessages OutgoingMessages ServerErrors ThrottledRequests \
  --interval PT5M --aggregation Maximum Total -o table || true

echo "== 11) Cambiar la configuración sin recrear (ejemplo: bajar entregas máximas) =="
az servicebus queue update -g "$RG" --namespace-name "$SB" -n pedidos-demo --max-delivery-count 5 -o none

echo "== 12) Limpieza de la práctica =="
# az servicebus queue delete -g "$RG" --namespace-name "$SB" -n pedidos-demo
# az servicebus topic delete -g "$RG" --namespace-name "$SB" -n eventos-demo
