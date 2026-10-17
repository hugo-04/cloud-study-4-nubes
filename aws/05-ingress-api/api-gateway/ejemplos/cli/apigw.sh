#!/usr/bin/env bash
# Operación de API Gateway HTTP API.
set -euo pipefail
API="${1:-}"
if [ -z "$API" ]; then
  echo "== APIs HTTP existentes =="
  aws apigatewayv2 get-apis --query "Items[].{id:ApiId, nombre:Name, endpoint:ApiEndpoint, protocolo:ProtocolType}" --output table
  echo "Uso: $0 <api-id>"; exit 0
fi

echo "== Rutas e integraciones =="
aws apigatewayv2 get-routes --api-id "$API" --query "Items[].{ruta:RouteKey, autorizador:AuthorizerId, destino:Target}" --output table

echo "== Etapas y límites =="
aws apigatewayv2 get-stages --api-id "$API" \
  --query "Items[].{etapa:StageName, autoDespliegue:AutoDeploy, limites:DefaultRouteSettings}" --output json

echo "== Autorizadores =="
aws apigatewayv2 get-authorizers --api-id "$API" \
  --query "Items[].{id:AuthorizerId, tipo:AuthorizerType, issuer:JwtConfiguration.Issuer, audiencia:JwtConfiguration.Audience}" --output json

cat <<'DOC'

== Comandos útiles (copiar y adaptar) ==
# Probar con un token:
curl -i -H "Authorization: Bearer $TOKEN" https://api.modalima.com/pedidos/P-1001

# Ver los logs de acceso (grupo configurado en la etapa):
aws logs tail /apigw/prod-tienda --follow --since 15m
aws logs filter-log-events --log-group-name /apigw/prod-tienda --filter-pattern '{ $.status >= 500 }' --max-items 20

# Métricas de 5XX y latencia (CloudWatch):
aws cloudwatch get-metric-statistics --namespace AWS/ApiGateway --metric-name 5xx --dimensions Name=ApiId,Value=<api-id> \
  --start-time $(date -u -d '-1 hour' +%FT%TZ) --end-time $(date -u +%FT%TZ) --period 300 --statistics Sum
DOC
