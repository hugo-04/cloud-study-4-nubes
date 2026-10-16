#!/usr/bin/env bash
# Event Hubs por CLI: namespace, event hubs, grupos, Capture, red, métricas y envío de prueba.
# Ejecuta por secciones. Requiere: az login y rol adecuado (Contributor para crear; Data Sender/Receiver para eventos).
set -euo pipefail

RG=rg-estudio-eventhubs
NS=evhns-modalima-XXXXXX           # salida "namespace" de Terraform (sin .servicebus.windows.net)
HUB=clics-web
LOC=eastus2
STG=stehmodalimaXXXXXX             # cuenta de Storage de Capture/checkpoints

echo "== 1) Namespace sin claves (solo Entra ID) con auto-inflate =="
# az eventhubs namespace create -g "$RG" -n "$NS" -l "$LOC" --sku Standard --capacity 2 \
#   --enable-auto-inflate true --maximum-throughput-units 6 --disable-local-auth true --min-tls-version 1.2
az eventhubs namespace show -g "$RG" -n "$NS" \
  --query '{sku:sku.name,tu:sku.capacity,autoInflate:isAutoInflateEnabled,maxTu:maximumThroughputUnits,sinClaves:disableLocalAuth,tls:minimumTlsVersion,publico:publicNetworkAccess,kafka:kafkaEnabled}' -o table

echo "== 2) Event hub con 8 particiones y 3 días de retención =="
az eventhubs eventhub create -g "$RG" --namespace-name "$NS" -n "${HUB}-demo" \
  --partition-count 8 --retention-time-in-hours 72 --cleanup-policy Delete -o none
az eventhubs eventhub show -g "$RG" --namespace-name "$NS" -n "${HUB}-demo" \
  --query '{particiones:partitionCount,retencionHoras:retentionDescription.retentionTimeInHours,estado:status}' -o table

echo "== 3) Grupos de consumidores (uno por microservicio) =="
for g in analitica antifraude busqueda reproceso; do
  az eventhubs eventhub consumer-group create -g "$RG" --namespace-name "$NS" --eventhub-name "${HUB}-demo" -n "$g" -o none
done
az eventhubs eventhub consumer-group list -g "$RG" --namespace-name "$NS" --eventhub-name "${HUB}-demo" --query '[].name' -o tsv

echo "== 4) Capture a Blob cada 5 minutos o 300 MB (identidad del namespace con rol Storage Blob Data Contributor) =="
az storage container create --account-name "$STG" -n capture-demo --auth-mode login -o none
az eventhubs eventhub update -g "$RG" --namespace-name "$NS" -n "${HUB}-demo" \
  --enable-capture true --capture-interval 300 --capture-size-limit 314572800 \
  --destination-name EventHubArchive.AzureBlockBlob \
  --storage-account "$STG" --blob-container capture-demo \
  --archive-name-format '{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}' \
  --skip-empty-archives true -o none || echo "(revisa los parámetros de identidad de Capture en tu versión de la CLI)"

echo "== 5) Comprobar que no hay claves (reglas de autorización) =="
az eventhubs namespace authorization-rule list -g "$RG" --namespace-name "$NS" --query '[].name' -o tsv || true

echo "== 6) Enviar un evento de prueba por REST con tu token de Entra ID (rol Data Sender) =="
TOKEN=$(az account get-access-token --resource https://eventhubs.azure.net --query accessToken -o tsv)
curl -sS -X POST "https://${NS}.servicebus.windows.net/${HUB}-demo/messages" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/atom+xml;type=entry;charset=utf-8" \
  -H 'BrokerProperties: {"PartitionKey":"u-42"}' \
  -d '{"eventId":"evt-1","clienteId":"u-42","pagina":"/home"}' -w "HTTP %{http_code}\n"

echo "== 7) Métricas: ingreso, egreso, limitación y errores (última hora) =="
ID=$(az eventhubs namespace show -g "$RG" -n "$NS" --query id -o tsv)
for m in IncomingMessages OutgoingMessages ThrottledRequests ServerErrors UserErrors CaptureBacklog; do
  echo "-- $m"
  az monitor metrics list --resource "$ID" --metric "$m" --interval PT5M --offset 1h --aggregation Total \
    --query 'value[0].timeseries[0].data[-3:].{hora:timeStamp,total:total}' -o table || true
done

echo "== 8) Red: cerrar el acceso público y permitir servicios de confianza =="
# az eventhubs namespace network-rule-set update -g "$RG" --namespace-name "$NS" \
#   --default-action Deny --public-network-access Disabled --enable-trusted-service-access true

echo "== 9) Kafka: probar con kcat (requiere claves habilitadas; en producción usa OAUTHBEARER desde tu aplicación) =="
cat <<'KCAT'
# Con local auth habilitado (solo pruebas):
CS="$(az eventhubs namespace authorization-rule keys list -g $RG --namespace-name $NS -n RootManageSharedAccessKey --query primaryConnectionString -o tsv)"
echo '{"eventId":"evt-2","clienteId":"u-7"}' | kcat -P -b $NS.servicebus.windows.net:9093 -t clics-web-demo -k u-7 \
  -X security.protocol=SASL_SSL -X sasl.mechanism=PLAIN -X sasl.username='$ConnectionString' -X sasl.password="$CS"
kcat -C -b $NS.servicebus.windows.net:9093 -t clics-web-demo -G herramientas -e \
  -X security.protocol=SASL_SSL -X sasl.mechanism=PLAIN -X sasl.username='$ConnectionString' -X sasl.password="$CS"
KCAT

echo "== 10) Limpieza =="
# az eventhubs eventhub delete -g "$RG" --namespace-name "$NS" -n "${HUB}-demo"
echo "ok"
