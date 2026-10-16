#!/usr/bin/env bash
# App Service de punta a punta (Linux, Java 21): plan, app, identidad, Key Vault, red, slots, autoescalado.
# Ejecuta por secciones. Verifica flags con `az webapp <cmd> --help` en tu versión de la CLI.
set -euo pipefail

RG=rg-estudio-compute
LOC=eastus2
PLAN=plan-modalima
APP=app-modalima-$RANDOM            # nombre único global (*.azurewebsites.net)
VNET=vnet-compute
SNET_INT=snet-appsvc-int            # subred DELEGADA para la salida (VNet Integration)
SNET_PE=snet-pe                     # subred para Private Endpoints

az group create -n "$RG" -l "$LOC" >/dev/null

echo "== 1) Plan y app =="
az appservice plan create -g "$RG" -n "$PLAN" --is-linux --sku P0v3
az webapp list-runtimes --os linux | grep -i java | head          # confirma la cadena del runtime
az webapp create -g "$RG" -p "$PLAN" -n "$APP" --runtime "JAVA:21-java21"

echo "== 2) Endurecer: HTTPS, TLS, FTP, Always On, health check =="
az webapp update -g "$RG" -n "$APP" --https-only true
az webapp config set -g "$RG" -n "$APP" \
  --always-on true --min-tls-version 1.2 --ftps-state Disabled --http20-enabled true \
  --generic-configurations '{"healthCheckPath": "/actuator/health/readiness"}'
az webapp update -g "$RG" -n "$APP" --client-affinity-enabled false      # API sin estado: sin ARR affinity
# Deshabilitar credenciales básicas de FTP y SCM (despliegue solo con Entra ID)
APPID=$(az webapp show -g "$RG" -n "$APP" --query id -o tsv)
for POL in ftp scm; do
  az resource update --ids "$APPID/basicPublishingCredentialsPolicies/$POL" --set properties.allow=false >/dev/null
done

echo "== 3) Identidad administrada (user-assigned) y referencias a Key Vault =="
az identity create -g "$RG" -n id-app-pedidos >/dev/null
UAMI_ID=$(az identity show -g "$RG" -n id-app-pedidos --query id -o tsv)
UAMI_CLIENT=$(az identity show -g "$RG" -n id-app-pedidos --query clientId -o tsv)
az webapp identity assign -g "$RG" -n "$APP" --identities "$UAMI_ID"
# Qué identidad usa la plataforma para resolver @Microsoft.KeyVault(...)
az rest --method PATCH --uri "https://management.azure.com${APPID}?api-version=2022-03-01" \
  --body "{\"properties\":{\"keyVaultReferenceIdentity\":\"${UAMI_ID}\"}}" >/dev/null
az webapp config appsettings set -g "$RG" -n "$APP" --settings \
  AZURE_CLIENT_ID="$UAMI_CLIENT" \
  SPRING_PROFILES_ACTIVE=prod \
  JAVA_OPTS="-XX:MaxRAMPercentage=70 -XX:+ExitOnOutOfMemoryError -Dnetworkaddress.cache.ttl=30" \
  DB_PASSWORD='@Microsoft.KeyVault(SecretUri=https://kv-modalima-estudio01.vault.azure.net/secrets/db-password/)' >/dev/null
# Ajustes pegajosos al slot (no viajan con el swap)
az webapp config appsettings set -g "$RG" -n "$APP" --slot-settings APP_ENTORNO=produccion >/dev/null

echo "== 4) Red: VNet + subredes, VNet Integration (salida) y Private Endpoint (entrada) =="
az network vnet create -g "$RG" -n "$VNET" --address-prefixes 10.70.0.0/16 \
  --subnet-name "$SNET_INT" --subnet-prefixes 10.70.1.0/26 >/dev/null
az network vnet subnet update -g "$RG" --vnet-name "$VNET" -n "$SNET_INT" \
  --delegations Microsoft.Web/serverFarms >/dev/null
az network vnet subnet create -g "$RG" --vnet-name "$VNET" -n "$SNET_PE" \
  --address-prefixes 10.70.2.0/27 --disable-private-endpoint-network-policies true >/dev/null
az webapp vnet-integration add -g "$RG" -n "$APP" --vnet "$VNET" --subnet "$SNET_INT"
# Que TODO el tráfico saliente pase por la VNet (para NAT Gateway / Firewall):
az webapp config set -g "$RG" -n "$APP" --generic-configurations '{"vnetRouteAllEnabled": true}'

# Entrada privada (opcional): Private Endpoint "sites" + zona privatelink.azurewebsites.net
az network private-endpoint create -g "$RG" -n pe-app --vnet-name "$VNET" --subnet "$SNET_PE" \
  --private-connection-resource-id "$APPID" --group-id sites --connection-name psc-app
az network private-dns zone create -g "$RG" -n privatelink.azurewebsites.net
az network private-dns link vnet create -g "$RG" -z privatelink.azurewebsites.net -n link-vnet \
  -v "$VNET" -e false
az network private-endpoint dns-zone-group create -g "$RG" --endpoint-name pe-app -n zona-app \
  --private-dns-zone privatelink.azurewebsites.net --zone-name privatelink.azurewebsites.net

# Alternativa sin Private Endpoint: solo permitir Front Door
#   az webapp config access-restriction add -g "$RG" -n "$APP" --rule-name solo-frontdoor \
#     --priority 100 --action Allow --service-tag AzureFrontDoor.Backend \
#     --http-headers x_azure_fdid=<ID_DE_TU_FRONT_DOOR>

echo "== 5) Slot de staging, despliegue y swap =="
az webapp deployment slot create -g "$RG" -n "$APP" --slot staging --configuration-source "$APP"
# az webapp deploy -g "$RG" -n "$APP" --slot staging --src-path target/app.jar --type jar
# Calentamiento durante el swap
az webapp config appsettings set -g "$RG" -n "$APP" --slot staging --settings \
  WEBSITE_SWAP_WARMUP_PING_PATH=/actuator/health/readiness WEBSITE_SWAP_WARMUP_PING_STATUSES=200 >/dev/null
# Probar con 10 % del tráfico en el slot:
#   az webapp traffic-routing set -g "$RG" -n "$APP" --distribution staging=10
# Swap (rollback = repetir el swap):
#   az webapp deployment slot swap -g "$RG" -n "$APP" --slot staging --target-slot production

echo "== 6) Autoescalado: mínimo 2, máximo 6, por CPU =="
PLANID=$(az appservice plan show -g "$RG" -n "$PLAN" --query id -o tsv)
az monitor autoscale create -g "$RG" --resource "$PLANID" --resource-type Microsoft.Web/serverFarms \
  -n autoscale-plan --min-count 2 --max-count 6 --count 2
az monitor autoscale rule create -g "$RG" --autoscale-name autoscale-plan \
  --condition "CpuPercentage > 70 avg 10m" --scale out 1
az monitor autoscale rule create -g "$RG" --autoscale-name autoscale-plan \
  --condition "CpuPercentage < 30 avg 15m" --scale in 1

echo "== 7) Logs y diagnóstico =="
az webapp log config -g "$RG" -n "$APP" --application-logging filesystem --level information \
  --web-server-logging filesystem
# az webapp log tail -g "$RG" -n "$APP"
LAW=$(az monitor log-analytics workspace create -g "$RG" -n law-compute -l "$LOC" --query id -o tsv)
az monitor diagnostic-settings create --name diag-app --resource "$APPID" --workspace "$LAW" \
  --logs '[{"category":"AppServiceHTTPLogs","enabled":true},{"category":"AppServiceConsoleLogs","enabled":true},{"category":"AppServicePlatformLogs","enabled":true}]'

echo "== 8) Variante con imagen de contenedor desde ACR (identidad, sin contraseña) =="
# az acr create -g "$RG" -n acrmodalima$RANDOM --sku Basic
# az role assignment create --assignee-object-id <principalId de id-app-pedidos> --assignee-principal-type ServicePrincipal \
#   --role AcrPull --scope <acrId>
# az webapp config container set -g "$RG" -n "$APP" \
#   --container-image-name acrmodalima.azurecr.io/api-pedidos:1.4.0 --container-registry-url https://acrmodalima.azurecr.io
# az webapp config set -g "$RG" -n "$APP" --generic-configurations \
#   "{\"acrUseManagedIdentityCreds\": true, \"acrUserManagedIdentityID\": \"$UAMI_CLIENT\"}"
# az webapp config appsettings set -g "$RG" -n "$APP" --settings WEBSITES_PORT=8080

echo "Listo: https://$APP.azurewebsites.net  |  Limpieza: az group delete -n $RG --yes --no-wait"
