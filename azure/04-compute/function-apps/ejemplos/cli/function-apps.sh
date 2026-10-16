#!/usr/bin/env bash
# Function App en Flex Consumption (Java 21) con identidad administrada de punta a punta.
# Ejecuta por secciones. Verifica flags con `az functionapp <cmd> --help` en tu versión de la CLI.
set -euo pipefail

RG=rg-estudio-compute
LOC=eastus2
ST=stfunc$RANDOM$RANDOM                 # 3-24 caracteres, minúsculas y números
FUNC=func-modalima-$RANDOM
UAMI=id-func-pedidos
SB=sb-func-$RANDOM

az group create -n "$RG" -l "$LOC" >/dev/null

echo "== 1) Storage del host: sin claves compartidas (solo identidad) =="
az storage account create -g "$RG" -n "$ST" -l "$LOC" --sku Standard_LRS \
  --allow-shared-key-access false --min-tls-version TLS1_2 --allow-blob-public-access false
STID=$(az storage account show -g "$RG" -n "$ST" --query id -o tsv)
az storage container create --account-name "$ST" -n app-package --auth-mode login   # paquete de despliegue (Flex)

echo "== 2) Identidad user-assigned y sus roles sobre el storage =="
az identity create -g "$RG" -n "$UAMI" >/dev/null
UAMI_ID=$(az identity show -g "$RG" -n "$UAMI" --query id -o tsv)
UAMI_PRINCIPAL=$(az identity show -g "$RG" -n "$UAMI" --query principalId -o tsv)
UAMI_CLIENT=$(az identity show -g "$RG" -n "$UAMI" --query clientId -o tsv)
for ROL in "Storage Blob Data Owner" "Storage Queue Data Contributor" "Storage Table Data Contributor"; do
  az role assignment create --assignee-object-id "$UAMI_PRINCIPAL" --assignee-principal-type ServicePrincipal \
    --role "$ROL" --scope "$STID" >/dev/null
done

echo "== 3) Function App Flex Consumption =="
az functionapp create -g "$RG" -n "$FUNC" \
  --storage-account "$ST" \
  --flexconsumption-location "$LOC" \
  --runtime java --runtime-version 21 \
  --instance-memory 2048 --maximum-instance-count 40 \
  --deployment-storage-name "$ST" --deployment-storage-container-name app-package \
  --deployment-storage-auth-type UserAssignedIdentity --deployment-storage-auth-value "$UAMI"
az functionapp identity assign -g "$RG" -n "$FUNC" --identities "$UAMI_ID" >/dev/null

echo "== 4) Service Bus (cola 'pedidos') y roles =="
az servicebus namespace create -g "$RG" -n "$SB" -l "$LOC" --sku Standard >/dev/null
az servicebus queue create -g "$RG" --namespace-name "$SB" -n pedidos --max-delivery-count 5 \
  --lock-duration PT1M --enable-dead-lettering-on-message-expiration true >/dev/null
az servicebus queue create -g "$RG" --namespace-name "$SB" -n facturas >/dev/null
SBID=$(az servicebus namespace show -g "$RG" -n "$SB" --query id -o tsv)
for ROL in "Azure Service Bus Data Receiver" "Azure Service Bus Data Sender"; do
  az role assignment create --assignee-object-id "$UAMI_PRINCIPAL" --assignee-principal-type ServicePrincipal \
    --role "$ROL" --scope "$SBID" >/dev/null
done

echo "== 5) App settings con conexiones POR IDENTIDAD (sin cadenas) =="
az functionapp config appsettings set -g "$RG" -n "$FUNC" --settings \
  AzureWebJobsStorage__accountName="$ST" \
  AzureWebJobsStorage__credential=managedidentity \
  AzureWebJobsStorage__clientId="$UAMI_CLIENT" \
  SBCONN__fullyQualifiedNamespace="$SB.servicebus.windows.net" \
  SBCONN__credential=managedidentity \
  SBCONN__clientId="$UAMI_CLIENT" \
  AZURE_CLIENT_ID="$UAMI_CLIENT" \
  KEYVAULT_URL="https://kv-modalima-estudio01.vault.azure.net" >/dev/null

echo "== 6) Escala: instancias siempre listas para HTTP y tope por seguridad =="
az functionapp scale config always-ready set -g "$RG" -n "$FUNC" --settings http=2
az functionapp scale config set -g "$RG" -n "$FUNC" --maximum-instance-count 40 --instance-memory 2048

echo "== 7) Red: VNet Integration (salida) hacia recursos privados =="
# az network vnet create -g "$RG" -n vnet-func --address-prefixes 10.80.0.0/16 --subnet-name snet-func --subnet-prefixes 10.80.1.0/26
# az network vnet subnet update -g "$RG" --vnet-name vnet-func -n snet-func --delegations Microsoft.App/environments
# az functionapp vnet-integration add -g "$RG" -n "$FUNC" --vnet vnet-func --subnet snet-func

echo "== 8) Desplegar el paquete =="
# mvn clean package && (cd target/azure-functions/$FUNC && zip -r ../../app.zip .)
# az functionapp deployment source config-zip -g "$RG" -n "$FUNC" --src target/app.zip
# o:  func azure functionapp publish "$FUNC"

echo "== 9) Autenticación de la plataforma (Entra ID) para las funciones HTTP =="
# az webapp auth microsoft update -g "$RG" -n "$FUNC" --client-id <APP_ID> --issuer https://login.microsoftonline.com/<TENANT>/v2.0
# az webapp auth update -g "$RG" -n "$FUNC" --enabled true --action RedirectToLoginPage

echo "== 10) Ver estado y funciones =="
az functionapp show -g "$RG" -n "$FUNC" --query "{estado:state, host:defaultHostName}" -o json
az functionapp function list -g "$RG" -n "$FUNC" -o table || true

echo "Limpieza: az group delete -n $RG --yes --no-wait"
