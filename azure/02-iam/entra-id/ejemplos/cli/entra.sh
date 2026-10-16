#!/usr/bin/env bash
# Entra ID: grupo, registro de una API con un app role, registro de un cliente y su permiso.
# Material de estudio. Requiere permisos de Application Developer/Administrator en el tenant.
set -euo pipefail

az account show --query "{tenant:tenantId,usuario:user.name}" -o table

# 1) Grupo de seguridad para asignar roles de Azure
GRUPO_ID=$(az ad group create --display-name "sg-desarrollo" --mail-nickname "sg-desarrollo" --query id -o tsv)
USUARIO_ID=$(az ad signed-in-user show --query id -o tsv)
az ad group member add --group "$GRUPO_ID" --member-id "$USUARIO_ID"

# 2) Registro de la API (resource server)
API_APPID=$(az ad app create --display-name "api-catalogo" --sign-in-audience AzureADMyOrg --query appId -o tsv)
az ad app update --id "$API_APPID" --identifier-uris "api://$API_APPID"
az ad sp create --id "$API_APPID" >/dev/null

# 3) App role "Catalogo.Read" para clientes de tipo aplicacion (servicio a servicio)
cat > /tmp/approles.json <<EOF
[{
  "allowedMemberTypes": ["Application"],
  "description": "Leer el catalogo",
  "displayName": "Catalogo.Read",
  "id": "$(python3 -c 'import uuid;print(uuid.uuid4())')",
  "isEnabled": true,
  "value": "Catalogo.Read"
}]
EOF
az ad app update --id "$API_APPID" --app-roles @/tmp/approles.json

# 4) Registro del cliente (otro microservicio) y su secreto de corta vida (solo para laboratorio)
CLI_APPID=$(az ad app create --display-name "svc-inventario" --sign-in-audience AzureADMyOrg --query appId -o tsv)
az ad sp create --id "$CLI_APPID" >/dev/null
# Preferible: identidad administrada o credencial federada. Un secreto solo para probar:
# az ad app credential reset --id "$CLI_APPID" --years 0 --append   # (ajusta la vigencia; no lo guardes en Git)

echo "API appId     : $API_APPID  (audiencia: api://$API_APPID)"
echo "Cliente appId : $CLI_APPID"
echo "Siguiente paso: dar al cliente el app role Catalogo.Read (portal: API permissions -> Add -> My APIs -> Application permissions) y conceder consentimiento de administrador."

# Limpieza
# az ad app delete --id "$API_APPID"; az ad app delete --id "$CLI_APPID"; az ad group delete --group "$GRUPO_ID"
