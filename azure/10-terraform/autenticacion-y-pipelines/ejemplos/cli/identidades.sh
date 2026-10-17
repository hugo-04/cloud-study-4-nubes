#!/usr/bin/env bash
# Identidades de Terraform para pipelines, con la CLI de Azure y la de GitHub.
# Léelo como una guía: cambia los valores de la sección "Variables" antes de ejecutar nada.
set -euo pipefail

# ---- Variables -----------------------------------------------------------------------
SUB_PLATAFORMA="00000000-0000-0000-0000-000000000000"
SUB_PROD="22222222-2222-2222-2222-222222222222"
RG="rg-identidades-terraform"
UBICACION="eastus2"
ORG_REPO="modalima/infra-azure"
ENTORNO="prod"
CUENTA_ESTADO_ID="/subscriptions/$SUB_PLATAFORMA/resourceGroups/rg-tfstate/providers/Microsoft.Storage/storageAccounts/stmodalimaprodtfstate01"

az account set --subscription "$SUB_PLATAFORMA"

# ---- 1. Identidades administradas asignadas por el usuario ----------------------------
az group create -n "$RG" -l "$UBICACION" -o none
for tipo in plan apply; do
  az identity create -g "$RG" -n "id-tf-$ENTORNO-$tipo" -l "$UBICACION" -o none
done

CLIENT_PLAN=$(az identity show -g "$RG" -n "id-tf-$ENTORNO-plan"  --query clientId    -o tsv)
PRINC_PLAN=$(az identity show  -g "$RG" -n "id-tf-$ENTORNO-plan"  --query principalId -o tsv)
CLIENT_APPLY=$(az identity show -g "$RG" -n "id-tf-$ENTORNO-apply" --query clientId    -o tsv)
PRINC_APPLY=$(az identity show  -g "$RG" -n "id-tf-$ENTORNO-apply" --query principalId -o tsv)
TENANT=$(az account show --query tenantId -o tsv)

# ---- 2. Credenciales federadas (el subject debe coincidir EXACTO con el pipeline) -----
az identity federated-credential create -g "$RG" --identity-name "id-tf-$ENTORNO-plan" \
  --name "gh-$ENTORNO-plan" \
  --issuer "https://token.actions.githubusercontent.com" \
  --subject "repo:$ORG_REPO:environment:$ENTORNO-plan" \
  --audiences "api://AzureADTokenExchange"

az identity federated-credential create -g "$RG" --identity-name "id-tf-$ENTORNO-apply" \
  --name "gh-$ENTORNO-apply" \
  --issuer "https://token.actions.githubusercontent.com" \
  --subject "repo:$ORG_REPO:environment:$ENTORNO" \
  --audiences "api://AzureADTokenExchange"

# Verifica lo que quedó registrado (un subject mal escrito NO da error aquí: falla después, en el login)
az identity federated-credential list -g "$RG" --identity-name "id-tf-$ENTORNO-apply" \
  --query "[].{nombre:name, issuer:issuer, subject:subject, audiencias:audiences}" -o table

# ---- 3. Roles sobre la suscripción de destino ----------------------------------------
az role assignment create --assignee-object-id "$PRINC_PLAN"  --assignee-principal-type ServicePrincipal \
  --role "Reader"      --scope "/subscriptions/$SUB_PROD"
az role assignment create --assignee-object-id "$PRINC_APPLY" --assignee-principal-type ServicePrincipal \
  --role "Contributor" --scope "/subscriptions/$SUB_PROD"

# Administrador de RBAC con condición: solo puede asignar Reader y Key Vault Secrets User
CONDICION="((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {acdd72a7-3385-48ef-bd42-f606fba81ae7, 4633458b-17de-408a-b874-0445c86b69e6})) AND ((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})) OR (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {acdd72a7-3385-48ef-bd42-f606fba81ae7, 4633458b-17de-408a-b874-0445c86b69e6}))"
az role assignment create --assignee-object-id "$PRINC_APPLY" --assignee-principal-type ServicePrincipal \
  --role "Role Based Access Control Administrator" --scope "/subscriptions/$SUB_PROD" \
  --condition "$CONDICION" --condition-version "2.0"

# ---- 4. Rol de DATOS sobre el contenedor del estado (el plan también toma el candado) --
CONTENEDOR="$CUENTA_ESTADO_ID/blobServices/default/containers/tfstate"
for p in "$PRINC_PLAN" "$PRINC_APPLY"; do
  az role assignment create --assignee-object-id "$p" --assignee-principal-type ServicePrincipal \
    --role "Storage Blob Data Owner" --scope "$CONTENEDOR"
done

# ---- 5. Variables del entorno en GitHub (no son secretos) -----------------------------
gh api -X PUT "repos/$ORG_REPO/environments/$ENTORNO-plan" >/dev/null
gh api -X PUT "repos/$ORG_REPO/environments/$ENTORNO"      >/dev/null     # añade revisores obligatorios en la interfaz
for v in "AZURE_TENANT_ID=$TENANT" "AZURE_SUBSCRIPTION_ID=$SUB_PROD"; do
  gh variable set "${v%%=*}" --env "$ENTORNO-plan" --repo "$ORG_REPO" --body "${v#*=}"
  gh variable set "${v%%=*}" --env "$ENTORNO"      --repo "$ORG_REPO" --body "${v#*=}"
done
gh variable set AZURE_CLIENT_ID --env "$ENTORNO-plan" --repo "$ORG_REPO" --body "$CLIENT_PLAN"
gh variable set AZURE_CLIENT_ID --env "$ENTORNO"      --repo "$ORG_REPO" --body "$CLIENT_APPLY"

# ---- 6. Diagnóstico ------------------------------------------------------------------
# Roles de una identidad (¿tiene el rol de datos sobre el contenedor?)
az role assignment list --assignee "$PRINC_APPLY" --all \
  --query "[].{rol:roleDefinitionName, ambito:scope, condicion:condition}" -o table

# Probar un login federado a mano (con un JWT obtenido del emisor; caduca en minutos)
# az login --service-principal -u "$CLIENT_APPLY" --tenant "$TENANT" --federated-token "$JWT" --allow-no-subscriptions

# Quién soy en este momento
az account show --query "{usuario:user.name, tipo:user.type, sub:id, tenant:tenantId}" -o json

# ---- 7. Revocar --------------------------------------------------------------------
# az identity federated-credential delete -g "$RG" --identity-name "id-tf-$ENTORNO-apply" --name "gh-$ENTORNO-apply" -y
