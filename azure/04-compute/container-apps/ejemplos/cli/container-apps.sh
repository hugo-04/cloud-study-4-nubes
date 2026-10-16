#!/usr/bin/env bash
# Container Apps de punta a punta: entorno en VNet, ACR sin contraseña, identidad, secretos desde Key Vault,
# reglas de escala (HTTP y Service Bus con identidad), Dapr, revisiones azul/verde y jobs.
# Ejecuta por secciones. Confirma flags con `az containerapp <cmd> --help` en tu versión de la CLI.
set -euo pipefail

RG=rg-estudio-aca
LOC=eastus2
ENV=cae-modalima
VNET=vnet-aca
SNET=snet-aca
ACR=acrmodalima$RANDOM
UAMI=id-aca-api
KV_SECRET_URL="${KV_SECRET_URL:-https://kv-modalima-estudio01.vault.azure.net/secrets/db-password}"

az group create -n "$RG" -l "$LOC" >/dev/null

echo "== 1) Red: subred delegada a Microsoft.App/environments =="
az network vnet create -g "$RG" -n "$VNET" --address-prefixes 10.100.0.0/16 \
  --subnet-name "$SNET" --subnet-prefixes 10.100.0.0/23 >/dev/null
az network vnet subnet update -g "$RG" --vnet-name "$VNET" -n "$SNET" --delegations Microsoft.App/environments >/dev/null
SUBNET_ID=$(az network vnet subnet show -g "$RG" --vnet-name "$VNET" -n "$SNET" --query id -o tsv)

echo "== 2) Logs, ACR e identidad =="
LAW_ID=$(az monitor log-analytics workspace create -g "$RG" -n law-aca -l "$LOC" --query customerId -o tsv)
LAW_KEY=$(az monitor log-analytics workspace get-shared-keys -g "$RG" -n law-aca --query primarySharedKey -o tsv)
az acr create -g "$RG" -n "$ACR" --sku Standard --admin-enabled false >/dev/null
ACR_ID=$(az acr show -n "$ACR" --query id -o tsv)
az identity create -g "$RG" -n "$UAMI" >/dev/null
UAMI_ID=$(az identity show -g "$RG" -n "$UAMI" --query id -o tsv)
UAMI_PRINCIPAL=$(az identity show -g "$RG" -n "$UAMI" --query principalId -o tsv)
UAMI_CLIENT=$(az identity show -g "$RG" -n "$UAMI" --query clientId -o tsv)
az role assignment create --assignee-object-id "$UAMI_PRINCIPAL" --assignee-principal-type ServicePrincipal \
  --role AcrPull --scope "$ACR_ID" >/dev/null

echo "== 3) Entorno (perfiles de carga, VNet; añade --internal-only true para ingress solo privado) =="
az containerapp env create -g "$RG" -n "$ENV" -l "$LOC" \
  --enable-workload-profiles true \
  --infrastructure-subnet-resource-id "$SUBNET_ID" \
  --logs-workspace-id "$LAW_ID" --logs-workspace-key "$LAW_KEY"
# Perfil dedicado opcional para cargas pesadas:
#   az containerapp env workload-profile add -g "$RG" -n "$ENV" --workload-profile-name d4 --workload-profile-type D4 --min-nodes 0 --max-nodes 3

echo "== 4) API: ACR por identidad, secreto de Key Vault, HTTP scale, probes vía YAML (ver ../yaml) =="
az containerapp create -g "$RG" -n api-pedidos --environment "$ENV" \
  --image mcr.microsoft.com/k8se/quickstart:latest --target-port 80 --ingress external \
  --user-assigned "$UAMI_ID" \
  --registry-server "$ACR.azurecr.io" --registry-identity "$UAMI_ID" \
  --cpu 1.0 --memory 2.0Gi \
  --min-replicas 1 --max-replicas 10 \
  --scale-rule-name http-50 --scale-rule-type http --scale-rule-http-concurrency 50 \
  --secrets "db-password=keyvaultref:${KV_SECRET_URL},identityref:${UAMI_ID}" \
  --env-vars DB_PASSWORD=secretref:db-password AZURE_CLIENT_ID="$UAMI_CLIENT" \
             JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=70 -XX:+ExitOnOutOfMemoryError"
# (la imagen de ejemplo es un quickstart; reemplázala por $ACR.azurecr.io/api-pedidos:1.4.0)
# Para sondas y configuración completa: az containerapp update -g "$RG" -n api-pedidos --yaml ../yaml/containerapp.yaml

echo "== 5) Worker de cola: escala 0..20 con regla de Service Bus autenticada por identidad =="
az containerapp create -g "$RG" -n worker-pedidos --environment "$ENV" \
  --image mcr.microsoft.com/k8se/quickstart:latest --ingress none \
  --user-assigned "$UAMI_ID" \
  --registry-server "$ACR.azurecr.io" --registry-identity "$UAMI_ID" \
  --cpu 0.5 --memory 1.0Gi --min-replicas 0 --max-replicas 20 \
  --scale-rule-name cola-pedidos --scale-rule-type azure-servicebus \
  --scale-rule-metadata queueName=pedidos namespace=sb-modalima messageCount=20 \
  --scale-rule-identity "$UAMI_ID"
# La identidad necesita "Azure Service Bus Data Receiver" sobre el namespace.

echo "== 6) Dapr: activar sidecar y definir un componente pub/sub =="
az containerapp dapr enable -g "$RG" -n api-pedidos --dapr-app-id api-pedidos --dapr-app-port 8080 --dapr-app-protocol http
az containerapp env dapr-component set -g "$RG" -n "$ENV" --dapr-component-name pubsub --yaml ../yaml/dapr-pubsub-servicebus.yaml

echo "== 7) Revisiones azul/verde =="
az containerapp revision set-mode -g "$RG" -n api-pedidos --mode multiple
az containerapp update -g "$RG" -n api-pedidos --revision-suffix v2 --image mcr.microsoft.com/k8se/quickstart:latest
az containerapp revision list -g "$RG" -n api-pedidos -o table
az containerapp ingress traffic set -g "$RG" -n api-pedidos --revision-weight api-pedidos--v2=10 latest=90
# Subir a 100 % v2, y entonces desactivar la vieja:
#   az containerapp ingress traffic set -g "$RG" -n api-pedidos --revision-weight api-pedidos--v2=100
#   az containerapp revision deactivate -g "$RG" -n api-pedidos --revision <revisión-vieja>
# Rollback: devolver el tráfico a la revisión anterior.

echo "== 8) Job programado: reporte diario =="
az containerapp job create -g "$RG" -n job-reporte --environment "$ENV" \
  --trigger-type Schedule --cron-expression "0 12 * * *" \
  --replica-timeout 1800 --replica-retry-limit 1 --replica-completion-count 1 --parallelism 1 \
  --image mcr.microsoft.com/k8se/quickstart-jobs:latest --cpu 0.5 --memory 1.0Gi \
  --mi-user-assigned "$UAMI_ID"
# Ejecutar a mano: az containerapp job start -g "$RG" -n job-reporte
# Historial:       az containerapp job execution list -g "$RG" -n job-reporte -o table

echo "== 9) Diagnóstico =="
az containerapp logs show -g "$RG" -n api-pedidos --tail 50 || true
az containerapp replica list -g "$RG" -n api-pedidos -o table || true
# Shell dentro de la réplica: az containerapp exec -g "$RG" -n api-pedidos --command sh

echo "Limpieza: az group delete -n $RG --yes --no-wait"
