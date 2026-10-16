#!/usr/bin/env bash
# Azure RBAC: asignar roles, rol personalizado y revisar accesos.
# Material de estudio. Reemplaza los valores entre <>.
set -euo pipefail

SUB=$(az account show --query id -o tsv)
RG=rg-estudio-iam
LOC=eastus2
az group create -n "$RG" -l "$LOC" >/dev/null

# 1) Asignar un rol de DATOS a un grupo, sobre un contenedor concreto
ST=stestudio$RANDOM$RANDOM
az storage account create -g "$RG" -n "$ST" -l "$LOC" --sku Standard_LRS --allow-blob-public-access false >/dev/null
az storage container create --account-name "$ST" -n fotos --auth-mode login >/dev/null 2>&1 || true

GRUPO_ID=<OBJECT-ID-DEL-GRUPO>
SCOPE="/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Storage/storageAccounts/$ST/blobServices/default/containers/fotos"

az role assignment create \
  --assignee-object-id "$GRUPO_ID" --assignee-principal-type Group \
  --role "Storage Blob Data Reader" --scope "$SCOPE"

# 2) Rol personalizado (soporte puede reiniciar App Services y ver metricas)
cat > /tmp/rol-soporte.json <<EOF
{
  "Name": "Soporte de Aplicaciones",
  "IsCustom": true,
  "Description": "Reinicia sitios web y lee metricas. Nada mas.",
  "Actions": [
    "Microsoft.Web/sites/read",
    "Microsoft.Web/sites/restart/action",
    "Microsoft.Insights/metrics/read"
  ],
  "NotActions": [],
  "DataActions": [],
  "NotDataActions": [],
  "AssignableScopes": ["/subscriptions/$SUB"]
}
EOF
az role definition create --role-definition @/tmp/rol-soporte.json

# 3) Auditar
az role assignment list --scope "/subscriptions/$SUB/resourceGroups/$RG" --include-inherited -o table
az role assignment list --all --query "[?roleDefinitionName=='Owner'].{quien:principalName,alcance:scope}" -o table

# Limpieza
# az role definition delete --name "Soporte de Aplicaciones"
# az group delete -n "$RG" --yes --no-wait
