#!/usr/bin/env bash
# APIM por CLI: crear, importar OpenAPI, política, producto/suscripción, diagnóstico y rastreo.
# Un APIM clásico tarda MUCHO en crearse (30-60 min). Ejecuta por secciones. Confirma flags con `az apim --help`.
set -euo pipefail

RG=rg-estudio-apim
APIM=apim-modalima-estudio
LOC=eastus2

echo "== 1) Crear el servicio (Developer = estudio, sin SLA) =="
az group create -n "$RG" -l "$LOC" >/dev/null
az apim create -g "$RG" -n "$APIM" -l "$LOC" \
  --publisher-email plataforma@modalima.example --publisher-name ModaLima \
  --sku-name Developer --no-wait
# Espera hasta que provisioningState sea Succeeded
az apim wait -g "$RG" -n "$APIM" --created

echo "== 2) Importar la API desde OpenAPI (con versión) =="
az apim api import -g "$RG" --service-name "$APIM" \
  --api-id pedidos-v1 --path pedidos --display-name "Pedidos" \
  --specification-format OpenApiJson --specification-path ../openapi/pedidos.json \
  --service-url https://api-interna.modalima.example/pedidos --api-version v1 --api-version-set-id pedidos

echo "== 3) Aplicar la política de la API (REST de ARM; la CLI no tiene un comando directo) =="
SUB=$(az account show --query id -o tsv)
POL=$(python3 - <<'PY'
import json
print(json.dumps({"properties": {"format": "rawxml", "value": open("../xml/10-api-policy.xml", encoding="utf-8").read()}}))
PY
)
az rest --method put \
  --url "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.ApiManagement/service/$APIM/apis/pedidos-v1/policies/policy?api-version=2022-08-01" \
  --body "$POL"

echo "== 4) Named value (secreto desde Key Vault) =="
az apim nv create -g "$RG" --service-name "$APIM" --named-value-id clave-proveedor --display-name clave-proveedor \
  --secret true --key-vault secret-identifier=https://kv-modalima-estudio01.vault.azure.net/secrets/clave-proveedor

echo "== 5) Producto y suscripción =="
az apim product create -g "$RG" --service-name "$APIM" --product-id socios-retail \
  --product-name "Socios Retail" --subscription-required true --approval-required true --state published
az apim product api add -g "$RG" --service-name "$APIM" --product-id socios-retail --api-id pedidos-v1
az apim subscription create -g "$RG" --service-name "$APIM" --sid distribuidor-x \
  --display-name "Distribuidor X" --scope "/products/socios-retail" --state active

echo "== 6) Obtener la clave y probar =="
CLAVE=$(az rest --method post \
  --url "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.ApiManagement/service/$APIM/subscriptions/distribuidor-x/listSecrets?api-version=2022-08-01" \
  --query primaryKey -o tsv)
GATEWAY=$(az apim show -g "$RG" -n "$APIM" --query gatewayUrl -o tsv)
curl -s -D - -H "Ocp-Apim-Subscription-Key: $CLAVE" "$GATEWAY/pedidos/v1/00000000-0000-0000-0000-000000000001" -o /dev/null

echo "== 7) Rastreo de una llamada (SOLO pruebas) =="
# Necesita la clave de suscripción de un administrador (all-access); la respuesta incluye Ocp-Apim-Trace-Location
curl -s -D - -H "Ocp-Apim-Subscription-Key: $CLAVE" -H "Ocp-Apim-Trace: true" "$GATEWAY/pedidos/v1/00000000-0000-0000-0000-000000000001" -o /dev/null | grep -i trace || true

echo "== 8) Estado y métricas =="
az apim show -g "$RG" -n "$APIM" --query "{estado:provisioningState, sku:sku.name, ipPublica:publicIpAddresses, red:virtualNetworkType}" -o table
az apim api list -g "$RG" --service-name "$APIM" -o table

echo "== 9) Limpieza (el soft-delete retiene el nombre unos días) =="
echo "az apim delete -g $RG -n $APIM --yes   # luego: az apim deletedservice purge --service-name $APIM --location $LOC"
