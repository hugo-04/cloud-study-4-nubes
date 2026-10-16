#!/usr/bin/env bash
# Claim Check por CLI: preparar el canal, subir un blob, publicar el ticket, consumir, DLQ y reproceso.
# Ejecuta por secciones. Requiere: az login, extensión servicebus no necesaria (usamos REST/az rest para mensajes).
set -euo pipefail

RG=rg-estudio-claimcheck
ST=stccXXXXXX                 # cambia por la salida "cuenta" de Terraform
SB=sb-cc-XXXXXX               # cambia por el nombre del namespace
COLA=archivos
SB_URL="https://${SB}.servicebus.windows.net"

echo "== 1) Estado del canal =="
az servicebus queue show -g "$RG" --namespace-name "$SB" -n "$COLA" \
  --query '{lock:lockDuration,maxEntregas:maxDeliveryCount,ttl:defaultMessageTimeToLive,duplicados:requiresDuplicateDetection,ventana:duplicateDetectionHistoryTimeWindow}' -o table

echo "== 2) Subir un blob (primero el blob) con etiqueta de estado y calcular su hash =="
ARCHIVO=catalogo.csv
printf 'sku,precio\nA1,10\nA2,20\n' > "$ARCHIVO"
ID=$(uuidgen)
BLOB="usuarios/u-42/$ID"
SHA=$(sha256sum "$ARCHIVO" | cut -d' ' -f1)
az storage blob upload --account-name "$ST" -c subidas -n "$BLOB" -f "$ARCHIVO" --auth-mode login \
  --content-type text/csv --tags estado=sin-confirmar -o none
VERSION=$(az storage blob show --account-name "$ST" -c subidas -n "$BLOB" --auth-mode login --query versionId -o tsv)
ETAG=$(az storage blob show --account-name "$ST" -c subidas -n "$BLOB" --auth-mode login --query etag -o tsv | tr -d '"')
TAM=$(stat -c%s "$ARCHIVO")
echo "id=$ID version=$VERSION sha256=$SHA"

echo "== 3) Construir y publicar el ticket (después del blob) =="
TICKET=$(cat <<JSON
{"mensajeId":"$ID","tipo":"archivo.recibido","version":1,
 "blobUrl":"https://${ST}.blob.core.windows.net/subidas/${BLOB}",
 "blobVersionId":"${VERSION}","etag":"${ETAG}","tamanoBytes":${TAM},
 "contentType":"text/csv","sha256":"${SHA}","propietario":"u-42",
 "correlacionId":"$(uuidgen)","creadoEn":"$(date -u +%FT%TZ)"}
JSON
)
TOKEN=$(az account get-access-token --resource https://servicebus.azure.net --query accessToken -o tsv)
curl -sS -X POST "${SB_URL}/${COLA}/messages" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "BrokerProperties: {\"MessageId\":\"$ID\",\"Label\":\"archivo.recibido\"}" \
  -d "$TICKET" -w "publicar: HTTP %{http_code}\n"
az storage blob tag set --account-name "$ST" -c subidas -n "$BLOB" --tags estado=publicado --auth-mode login -o none

echo "== 4) Publicar el MISMO ticket otra vez: la detección de duplicados lo descarta (ventana 10 min) =="
curl -sS -X POST "${SB_URL}/${COLA}/messages" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -H "BrokerProperties: {\"MessageId\":\"$ID\"}" -d "$TICKET" -w "duplicado: HTTP %{http_code} (aceptado y descartado por el broker)\n"

echo "== 5) Cuántos mensajes hay (activos, en DLQ) =="
az servicebus queue show -g "$RG" --namespace-name "$SB" -n "$COLA" \
  --query '{activos:countDetails.activeMessageCount,dlq:countDetails.deadLetterMessageCount,programados:countDetails.scheduledMessageCount}' -o table

echo "== 6) Recibir con bloqueo (peek-lock) y completar: lo hace el consumidor Java; aquí solo vemos sin consumir =="
curl -sS -X POST "${SB_URL}/${COLA}/messages/head?timeout=30" -H "Authorization: Bearer $TOKEN" -D - -o /tmp/ticket-recibido.json | grep -iE 'HTTP/|brokerproperties|location' || true
echo "(el 'Location' de la respuesta es el que se usa para completar con DELETE o abandonar con PUT)"

echo "== 7) Verificar el blob contra el ticket (lo que hace el consumidor) =="
az storage blob download --account-name "$ST" -c subidas -n "$BLOB" --version-id "$VERSION" -f /tmp/descarga.csv --auth-mode login -o none
test "$(sha256sum /tmp/descarga.csv | cut -d' ' -f1)" = "$SHA" && echo "hash OK" || echo "hash DISTINTO -> dead-letter HASH_INVALIDO"

echo "== 8) Simular BLOB_AUSENTE: borrar el blob antes de consumir =="
# az storage blob delete --account-name "$ST" -c subidas -n "$BLOB" --auth-mode login   # con versionado queda la versión anterior

echo "== 9) Ver la DLQ y su motivo (peek) =="
curl -sS -X POST "${SB_URL}/${COLA}/\$deadletterqueue/messages/head?timeout=5" -H "Authorization: Bearer $TOKEN" -D - -o /tmp/dlq.json \
  | grep -iE 'HTTP/|deadletter' || true

echo "== 10) Reproceso de la DLQ: el consumidor de reproceso lee de <cola>/\$deadletterqueue y reenvía a '$COLA' =="
echo "Ver uso-en-java.md y troubleshooting.md. Primero corrige la causa."

echo "== 11) Alertas recomendadas =="
az monitor metrics list --resource "$(az servicebus namespace show -g "$RG" -n "$SB" --query id -o tsv)" \
  --metric DeadletteredMessages ActiveMessages --interval PT5M --aggregation Maximum -o table || true

echo "== 12) Limpieza de la práctica =="
# az group delete -n "$RG" --yes --no-wait
