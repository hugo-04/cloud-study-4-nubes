#!/usr/bin/env bash
# Front Door (Standard/Premium) por CLI: crear lo mínimo, diagnosticar y operar.
# Confirma flags con `az afd --help` en tu versión de la CLI.
set -euo pipefail

RG=rg-estudio-afd
PERFIL=afd-modalima
EP=ep-modalima
OG=og-pedidos
ORIGEN=app-pedidos-modalima.azurewebsites.net

echo "== 1) Perfil, endpoint, grupo de orígenes y origen =="
az group create -n "$RG" -l eastus2 >/dev/null
az afd profile create -g "$RG" --profile-name "$PERFIL" --sku Premium_AzureFrontDoor
az afd endpoint create -g "$RG" --profile-name "$PERFIL" --endpoint-name "$EP" --enabled-state Enabled
az afd origin-group create -g "$RG" --profile-name "$PERFIL" --origin-group-name "$OG" \
  --probe-request-type HEAD --probe-protocol Https --probe-path /livez --probe-interval-in-seconds 60 \
  --sample-size 4 --successful-samples-required 3 --additional-latency-in-milliseconds 50
az afd origin create -g "$RG" --profile-name "$PERFIL" --origin-group-name "$OG" --origin-name principal \
  --host-name "$ORIGEN" --origin-host-header "$ORIGEN" --priority 1 --weight 100 \
  --enabled-state Enabled --https-port 443 --http-port 80 --enable-private-link false

echo "== 2) Ruta =="
az afd route create -g "$RG" --profile-name "$PERFIL" --endpoint-name "$EP" --route-name ruta-api \
  --origin-group "$OG" --supported-protocols Http Https --https-redirect Enabled \
  --forwarding-protocol HttpsOnly --patterns-to-match "/*" --link-to-default-domain Enabled

echo "== 3) Dominio personalizado (certificado gestionado) =="
az afd custom-domain create -g "$RG" --profile-name "$PERFIL" --custom-domain-name api-modalima \
  --host-name api.modalima.example --minimum-tls-version TLS12 --certificate-type ManagedCertificate
az afd custom-domain show -g "$RG" --profile-name "$PERFIL" --custom-domain-name api-modalima \
  --query "{estado:domainValidationState, token:validationProperties.validationToken}" -o table
# Crea en tu DNS: TXT _dnsauth.api = <token>   y   CNAME api → <endpoint>.z01.azurefd.net

echo "== 4) Diagnóstico =="
az afd endpoint show -g "$RG" --profile-name "$PERFIL" --endpoint-name "$EP" --query "{host:hostName, estado:deploymentStatus}" -o table
az afd origin list -g "$RG" --profile-name "$PERFIL" --origin-group-name "$OG" -o table
az afd profile show -g "$RG" --profile-name "$PERFIL" --query frontDoorId -o tsv    # valor de X-Azure-FDID

echo "== 5) Purgar caché tras un despliegue =="
az afd endpoint purge -g "$RG" --profile-name "$PERFIL" --endpoint-name "$EP" --content-paths "/static/*" "/img/*"

echo "== 6) Probar =="
curl -sI https://"$(az afd endpoint show -g "$RG" --profile-name "$PERFIL" --endpoint-name "$EP" --query hostName -o tsv)"/livez | grep -i -E "HTTP|x-azure-ref|x-cache"
echo "El origen directo debe estar cerrado:"
curl -skI https://"$ORIGEN"/ | head -1
