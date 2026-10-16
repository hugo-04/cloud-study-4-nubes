#!/usr/bin/env bash
# Blob Storage por CLI: cuenta segura, protección de datos, ciclo de vida, red privada, AzCopy y diagnóstico.
# Ejecuta por secciones. Confirma flags con `az storage account create --help` en tu versión de la CLI.
set -euo pipefail

RG=rg-estudio-storage
ST=stmodalimaestudio01          # único global, 3-24 caracteres, minúsculas y números
LOC=eastus2

echo "== 1) Cuenta segura =="
az group create -n "$RG" -l "$LOC" >/dev/null
az storage account create -g "$RG" -n "$ST" -l "$LOC" \
  --sku Standard_ZRS --kind StorageV2 --access-tier Hot \
  --allow-blob-public-access false \
  --allow-shared-key-access false \
  --min-tls-version TLS1_2 \
  --https-only true \
  --default-action Deny --bypass AzureServices

# Tu usuario necesita un rol de DATOS para operar con --auth-mode login
ME=$(az ad signed-in-user show --query id -o tsv)
STID=$(az storage account show -g "$RG" -n "$ST" --query id -o tsv)
az role assignment create --assignee-object-id "$ME" --assignee-principal-type User \
  --role "Storage Blob Data Contributor" --scope "$STID"

echo "== 2) Protección: soft delete, versionado, change feed, restauración puntual =="
az storage account blob-service-properties update -g "$RG" --account-name "$ST" \
  --enable-delete-retention true --delete-retention-days 14 \
  --enable-container-delete-retention true --container-delete-retention-days 14 \
  --enable-versioning true --enable-change-feed true \
  --enable-restore-policy true --restore-days 7

echo "== 3) Contenedores y subida =="
az storage container create --account-name "$ST" -n fotos   --auth-mode login
az storage container create --account-name "$ST" -n subidas --auth-mode login
az storage blob upload --account-name "$ST" -c fotos -f foto.jpg -n 2026/10/foto.jpg \
  --auth-mode login --content-type image/jpeg --tags estado=pendiente

echo "== 4) Etiquetas, tier y búsqueda por etiquetas =="
az storage blob tag set --account-name "$ST" -c fotos -n 2026/10/foto.jpg --tags estado=procesado --auth-mode login
az storage blob set-tier --account-name "$ST" -c fotos -n 2026/10/foto.jpg --tier Cool --auth-mode login
az storage blob filter --account-name "$ST" --tag-filter "\"estado\"='procesado'" --auth-mode login -o table

echo "== 5) Ciclo de vida =="
az storage account management-policy create -g "$RG" --account-name "$ST" --policy @lifecycle.json

echo "== 6) Inmutabilidad (WORM) para un contenedor de respaldos =="
az storage container create --account-name "$ST" -n respaldos --auth-mode login
az storage container immutability-policy create --account-name "$ST" -g "$RG" -c respaldos \
  --period 30 --allow-protected-append-writes true

echo "== 7) Red privada: Private Endpoint (zona DNS privada: ver capítulo de red) =="
# az network private-endpoint create ... --group-id blob --private-connection-resource-id "$STID"
# az storage account update -g "$RG" -n "$ST" --public-network-access Disabled

echo "== 8) Copias masivas con AzCopy (identidad de Entra ID, sin claves) =="
echo 'azcopy login'
echo "azcopy copy './datos/*' 'https://$ST.blob.core.windows.net/subidas/entrada/' --recursive --block-size-mb 16"
echo "azcopy sync './datos' 'https://$ST.blob.core.windows.net/subidas/entrada/' --delete-destination=false"

echo "== 9) Diagnóstico: logs hacia Log Analytics =="
LAW=$(az monitor log-analytics workspace create -g "$RG" -n law-storage -l "$LOC" --query id -o tsv)
az monitor diagnostic-settings create -n diag-blob --resource "$STID/blobServices/default" --workspace "$LAW" \
  --logs '[{"category":"StorageRead","enabled":true},{"category":"StorageWrite","enabled":true},{"category":"StorageDelete","enabled":true}]' \
  --metrics '[{"category":"Transaction","enabled":true}]'

echo "== 10) Comprobaciones =="
az storage account show -g "$RG" -n "$ST" \
  --query "{sku:sku.name, publico:allowBlobPublicAccess, claveCompartida:allowSharedKeyAccess, tls:minimumTlsVersion, red:networkRuleSet.defaultAction}" -o table
az storage blob list --account-name "$ST" -c fotos --prefix 2026/ --auth-mode login -o table
az storage blob show --account-name "$ST" -c fotos -n 2026/10/foto.jpg --auth-mode login --query "{tier:properties.blobTier, etag:properties.etag, tamano:properties.contentLength}" -o table
