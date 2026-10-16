#!/usr/bin/env bash
# Key Vault de punta a punta con la CLI: vault seguro, secretos, claves con rotación,
# certificados, red, auditoría y eventos. Ejecuta por secciones, no todo de golpe.
# Verifica los flags con `az keyvault <comando> --help` en tu versión de la CLI.
set -euo pipefail

RG=rg-estudio-sec
LOC=eastus2
KV=kv-modalima-$RANDOM$RANDOM          # nombre único global (3-24 caracteres)
MI_ID="${MI_PRINCIPAL_ID:-}"            # principalId de la identidad de la app (ver Managed Identity)
MI_NOMBRE=id-api-pedidos

az group create -n "$RG" -l "$LOC" >/dev/null

echo "== 1) Crear el vault: RBAC, soft delete 30 días, purge protection =="
az keyvault create -g "$RG" -n "$KV" -l "$LOC" \
  --enable-rbac-authorization true \
  --retention-days 30 \
  --enable-purge-protection true
KVID=$(az keyvault show -n "$KV" --query id -o tsv)

echo "== 2) Darte permiso de operador (sin esto no puedes crear secretos aunque seas Owner) =="
YO=$(az ad signed-in-user show --query id -o tsv)
az role assignment create --assignee-object-id "$YO" --assignee-principal-type User \
  --role "Key Vault Secrets Officer" --scope "$KVID"
echo "Espera 1-2 minutos a que el rol se propague."

echo "== 3) Secretos: crear con expiración, leer, versiones, deshabilitar =="
az keyvault secret set --vault-name "$KV" -n db-password --value 'cambia-esto' \
  --expires "$(date -u -d '+90 days' +%Y-%m-%dT%H:%M:%SZ)" \
  --content-type "text/plain" --tags dueno=equipo-pedidos entorno=estudio
az keyvault secret show --vault-name "$KV" -n db-password --query "{id:id, vence:attributes.expires, activo:attributes.enabled}" -o json
az keyvault secret list-versions --vault-name "$KV" -n db-password -o table
az keyvault secret set-attributes --vault-name "$KV" -n db-password --enabled false   # deshabilitar sin borrar
az keyvault secret set-attributes --vault-name "$KV" -n db-password --enabled true

echo "== 4) Dar lectura a la identidad de la aplicación (solo ESE secreto) =="
if [ -n "$MI_ID" ]; then
  SECRET_ID=$(az keyvault secret show --vault-name "$KV" -n db-password --query id -o tsv | sed 's#/[^/]*$##')
  az role assignment create --assignee-object-id "$MI_ID" --assignee-principal-type ServicePrincipal \
    --role "Key Vault Secrets User" --scope "$SECRET_ID"
fi

echo "== 5) Borrar y recuperar (soft delete) =="
az keyvault secret delete --vault-name "$KV" -n db-password
az keyvault secret list-deleted --vault-name "$KV" -o table
az keyvault secret recover --vault-name "$KV" -n db-password
# Con purge protection NO puedes purgar antes de que pase la retención (esa es la idea).

echo "== 6) Claves: crear RSA, política de rotación, rotar a mano =="
az role assignment create --assignee-object-id "$YO" --assignee-principal-type User \
  --role "Key Vault Crypto Officer" --scope "$KVID"
az keyvault key create --vault-name "$KV" -n k-reportes --kty RSA --size 3072 \
  --ops wrapKey unwrapKey encrypt decrypt
cat > /tmp/rotacion.json <<'JSON'
{
  "lifetimeActions": [
    { "trigger": { "timeAfterCreate": "P90D" },  "action": { "type": "Rotate" } },
    { "trigger": { "timeBeforeExpiry": "P30D" }, "action": { "type": "Notify" } }
  ],
  "attributes": { "expiryTime": "P1Y" }
}
JSON
az keyvault key rotation-policy update --vault-name "$KV" -n k-reportes --value @/tmp/rotacion.json
az keyvault key rotate --vault-name "$KV" -n k-reportes
az keyvault key list-versions --vault-name "$KV" -n k-reportes -o table

echo "== 7) Certificados: política por defecto (autofirmado) =="
az role assignment create --assignee-object-id "$YO" --assignee-principal-type User \
  --role "Key Vault Certificates Officer" --scope "$KVID"
az keyvault certificate create --vault-name "$KV" -n cert-demo \
  --policy "$(az keyvault certificate get-default-policy)"
az keyvault certificate show --vault-name "$KV" -n cert-demo --query "{vence:attributes.expires, id:id}" -o json
# Descargar certificado + clave privada: se pide como SECRETO del mismo nombre
az keyvault secret download --vault-name "$KV" -n cert-demo --file /tmp/cert-demo.pfx --encoding base64

echo "== 8) Red: firewall por defecto en Deny y tu IP =="
MI_IP=$(curl -s https://api.ipify.org || true)
az keyvault update -n "$KV" --default-action Deny --bypass AzureServices
[ -n "$MI_IP" ] && az keyvault network-rule add -n "$KV" --ip-address "$MI_IP/32"
# Para cerrar del todo y usar solo Private Endpoint:
#   az keyvault update -n "$KV" --public-network-access Disabled
# Private Endpoint (subrecurso "vault") + zona privatelink.vaultcore.azure.net:
#   ver ../../../01-red/private-endpoint-dns/ejemplos/cli

echo "== 9) Auditoría: AuditEvent hacia Log Analytics =="
LAW=$(az monitor log-analytics workspace create -g "$RG" -n law-estudio-sec -l "$LOC" --query id -o tsv)
az monitor diagnostic-settings create --name diag-kv --resource "$KVID" --workspace "$LAW" \
  --logs '[{"category":"AuditEvent","enabled":true}]'
# Consulta en Log Analytics (KQL):
#   AzureDiagnostics | where ResourceProvider == "MICROSOFT.KEYVAULT" and OperationName == "SecretGet"
#   | summarize n=count() by CallerIPAddress, identity_claim_appid_g, ResultSignature

echo "== 10) Eventos: avisar cuando un secreto esté por vencer =="
az eventgrid system-topic create -g "$RG" -n st-kv -l "$LOC" \
  --source "$KVID" --topic-type microsoft.keyvault.vaults
# Suscribe un webhook / Function / Service Bus (ejemplo con webhook):
#   az eventgrid system-topic event-subscription create -g "$RG" --system-topic-name st-kv \
#     --name sub-near-expiry --endpoint https://mi-funcion.azurewebsites.net/api/rotar \
#     --included-event-types Microsoft.KeyVault.SecretNearExpiry

echo "== 11) Copia de seguridad de un secreto =="
az keyvault secret backup --vault-name "$KV" -n db-password --file /tmp/db-password.bak
# Solo se restaura en la misma suscripción y geografía: az keyvault secret restore --vault-name ... --file ...

echo "Listo. Vault: $KV   |   Limpieza: az group delete -n $RG --yes --no-wait"
echo "Ojo: con purge protection el nombre del vault queda reservado hasta que pase la retención."
