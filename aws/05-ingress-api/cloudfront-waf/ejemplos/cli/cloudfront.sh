#!/usr/bin/env bash
# Operación de CloudFront y WAF.
set -euo pipefail
ID="${1:-}"
if [ -z "$ID" ]; then
  echo "== Distribuciones =="
  aws cloudfront list-distributions --query "DistributionList.Items[].{id:Id, dominio:DomainName, alias:Aliases.Items, estado:Status}" --output table
  echo "Uso: $0 <distribution-id>"; exit 0
fi

echo "== Configuración clave =="
aws cloudfront get-distribution --id "$ID" \
  --query "Distribution.DistributionConfig.{orígenes:Origins.Items[].DomainName, waf:WebACLId, tls:ViewerCertificate.MinimumProtocolVersion, claseDePrecio:PriceClass}" --output json

echo "== Invalidaciones recientes =="
aws cloudfront list-invalidations --distribution-id "$ID" --query "InvalidationList.Items[:5].{id:Id, estado:Status, creada:CreateTime}" --output table

cat <<'DOC'

== Comandos útiles (copiar y adaptar) ==
# Invalidar solo lo que apunta a archivos versionados:
aws cloudfront create-invalidation --distribution-id <ID> --paths "/index.html" "/config.json"

# Comprobar si una respuesta vino de caché (busca X-Cache y Age):
curl -sI https://www.modalima.com/static/app.3f9a1c.js | grep -iE "x-cache|age|cache-control"

# WAF (alcance CLOUDFRONT => región us-east-1): reglas y muestras de peticiones bloqueadas
aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1
aws wafv2 get-sampled-requests --web-acl-arn <arn> --rule-metric-name rate-login --scope CLOUDFRONT --region us-east-1 \
  --time-window StartTime=$(date -u -d '-1 hour' +%FT%TZ),EndTime=$(date -u +%FT%TZ) --max-items 20

# Generar un par de claves para URLs firmadas (la privada va a Secrets Manager; la pública, a un grupo de claves):
openssl genrsa -out privada.pem 2048 && openssl rsa -pubout -in privada.pem -out publica.pem
openssl pkcs8 -topk8 -nocrypt -in privada.pem -out privada-pkcs8.pem   # formato que lee el código Java
DOC
