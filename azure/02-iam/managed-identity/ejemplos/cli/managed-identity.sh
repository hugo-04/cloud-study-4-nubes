#!/usr/bin/env bash
# Managed Identity user-assigned: crear, dar rol de datos y asignarla a una Web App.
# Material de estudio.
set -euo pipefail

RG=rg-estudio-mi
LOC=eastus2
SUFIJO=$RANDOM$RANDOM
ST=stmi$SUFIJO
PLAN=plan-estudio-mi
APP=app-estudio-mi-$SUFIJO

az group create -n "$RG" -l "$LOC" >/dev/null

# 1) Identidad user-assigned
az identity create -g "$RG" -n id-api-pedidos >/dev/null
PRINCIPAL=$(az identity show -g "$RG" -n id-api-pedidos --query principalId -o tsv)
CLIENT=$(az identity show -g "$RG" -n id-api-pedidos --query clientId -o tsv)
IDENT_ID=$(az identity show -g "$RG" -n id-api-pedidos --query id -o tsv)

# 2) Storage sin claves de cuenta + rol de datos para la identidad
az storage account create -g "$RG" -n "$ST" -l "$LOC" --sku Standard_LRS \
  --allow-blob-public-access false --allow-shared-key-access false >/dev/null
STID=$(az storage account show -g "$RG" -n "$ST" --query id -o tsv)

az role assignment create --assignee-object-id "$PRINCIPAL" \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Reader" --scope "$STID"

# 3) Web App con esa identidad
az appservice plan create -g "$RG" -n "$PLAN" --is-linux --sku B1 >/dev/null
az webapp create -g "$RG" -p "$PLAN" -n "$APP" --runtime "JAVA:21-java21" >/dev/null
az webapp identity assign -g "$RG" -n "$APP" --identities "$IDENT_ID"
az webapp config appsettings set -g "$RG" -n "$APP" \
  --settings AZURE_CLIENT_ID="$CLIENT" STORAGE_ACCOUNT="$ST" >/dev/null

echo "La app $APP usa la identidad con clientId $CLIENT (sin secretos)."
echo "Espera unos minutos a que el rol se propague antes de probar."

# Limpieza: az group delete -n "$RG" --yes --no-wait
