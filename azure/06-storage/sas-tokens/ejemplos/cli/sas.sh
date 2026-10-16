#!/usr/bin/env bash
# SAS por CLI: delegación de usuario (recomendada), política almacenada (servicio), revocación y pruebas con curl.
# Ejecuta por secciones. En macOS usa: date -u -v+15M '+%Y-%m-%dT%H:%MZ'
set -euo pipefail

RG=rg-estudio-storage
ST=stmodalimaestudio01
exp() { date -u -d "+$1 minutes" '+%Y-%m-%dT%H:%MZ'; }

echo "== 1) SAS de LECTURA de un blob, 15 minutos (delegación de usuario: NO usa la clave de la cuenta) =="
URL_LECTURA=$(az storage blob generate-sas --account-name "$ST" -c fotos -n 2026/10/foto.jpg \
  --permissions r --https-only --as-user --auth-mode login --full-uri --expiry "$(exp 15)" -o tsv)
echo "$URL_LECTURA" | sed 's/sig=[^&]*/sig=***/'

echo "== 2) SAS de ESCRITURA (blob nuevo), 15 minutos =="
URL_ESCRITURA=$(az storage blob generate-sas --account-name "$ST" -c subidas -n "entrada/pedido-$(uuidgen).pdf" \
  --permissions cw --https-only --as-user --auth-mode login --full-uri --expiry "$(exp 15)" -o tsv)

echo "== 3) Usarlas =="
curl -sS -o /tmp/foto.jpg -w "descarga: HTTP %{http_code}\n" "$URL_LECTURA"
curl -sS -X PUT -H "x-ms-blob-type: BlockBlob" -H "Content-Type: application/pdf" \
  --data-binary @pedido-123.pdf -w "subida: HTTP %{http_code}\n" "$URL_ESCRITURA"

echo "== 4) SAS con restricción de IP y nombre de descarga =="
az storage blob generate-sas --account-name "$ST" -c fotos -n 2026/10/boleta.pdf \
  --permissions r --https-only --as-user --auth-mode login --full-uri --expiry "$(exp 5)" \
  --ip 203.0.113.0-203.0.113.255 --content-disposition 'attachment; filename="boleta-123.pdf"' --content-type application/pdf

echo "== 5) SAS de contenedor para listar (l) y subir muchos archivos a un prefijo (cw) =="
az storage container generate-sas --account-name "$ST" -n subidas --permissions lcw --https-only --as-user --auth-mode login \
  --expiry "$(exp 30)" --full-uri

echo "== 6) Política de acceso almacenada (servicio): revocable borrándola =="
# Requiere clave de cuenta o --auth-mode login con permisos de administración del contenedor
az storage container policy create --account-name "$ST" -c subidas -n proveedor-x \
  --permissions cw --expiry "$(date -u -d '+7 days' '+%Y-%m-%dT%H:%MZ')" --auth-mode login
# SAS de servicio ligada a la política (necesita la clave de la cuenta; no funciona si allowSharedKeyAccess=false)
# az storage container generate-sas --account-name $ST -n subidas --policy-name proveedor-x --account-key "$KEY" --full-uri
az storage container policy list --account-name "$ST" -c subidas --auth-mode login -o table

echo "== 7) REVOCAR =="
# a) Todas las SAS de delegación vigentes (afecta a TODAS las emitidas con claves de delegación):
az storage account revoke-delegation-keys -g "$RG" -n "$ST"
# b) Las ligadas a la política almacenada:
az storage container policy delete --account-name "$ST" -c subidas -n proveedor-x --auth-mode login

echo "== 8) Inspeccionar una SAS (qué dice, sin llamar al servicio) =="
python3 - "$URL_LECTURA" <<'PY'
import sys, urllib.parse
q = dict(urllib.parse.parse_qsl(urllib.parse.urlparse(sys.argv[1]).query))
for k in ("sv", "st", "se", "sr", "sp", "spr", "sip", "skoid", "ske", "rscd"):
    if k in q: print(f"{k:6} = {q[k]}")
PY
