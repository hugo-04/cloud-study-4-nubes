#!/usr/bin/env bash
# Grupos de administración con Azure CLI (versión de estudio). Es una guía de comandos, no la ejecutes de golpe.
set -euo pipefail

TENANT_ID="$(az account show --query tenantId -o tsv)"
RAIZ="mg-modalima"

# ---------------------------------------------------------------------------------------------
# 1) CREAR la jerarquía (el ID del grupo NO se puede cambiar después)
# ---------------------------------------------------------------------------------------------
az account management-group check-name-availability --name "$RAIZ"

az account management-group create --name "$RAIZ"                       --display-name "ModaLima"
az account management-group create --name "$RAIZ-plataforma"           --display-name "Plataforma"     --parent "$RAIZ"
az account management-group create --name "$RAIZ-identidad"            --display-name "Identidad"      --parent "$RAIZ-plataforma"
az account management-group create --name "$RAIZ-conectividad"         --display-name "Conectividad"   --parent "$RAIZ-plataforma"
az account management-group create --name "$RAIZ-gestion"              --display-name "Gestión"        --parent "$RAIZ-plataforma"
az account management-group create --name "$RAIZ-landingzones"        --display-name "Landing zones"  --parent "$RAIZ"
az account management-group create --name "$RAIZ-corp"                 --display-name "Corp"           --parent "$RAIZ-landingzones"
az account management-group create --name "$RAIZ-online"               --display-name "Online"         --parent "$RAIZ-landingzones"
az account management-group create --name "$RAIZ-sandbox"              --display-name "Sandbox"        --parent "$RAIZ"
az account management-group create --name "$RAIZ-desmantelado"         --display-name "Desmantelado"   --parent "$RAIZ"

# ---------------------------------------------------------------------------------------------
# 2) VER la jerarquía
# ---------------------------------------------------------------------------------------------
az account management-group list -o table
az account management-group show --name "$RAIZ" --expand --recurse -o jsonc     # árbol completo hacia abajo
az account management-group entities list -o table                              # grupos y suscripciones que ves
az account management-group subscription show-sub-under-mg --name "$RAIZ-corp"  # suscripciones directas del grupo

# ---------------------------------------------------------------------------------------------
# 3) MOVER suscripciones (ensaya antes el efecto de las políticas del grupo destino)
# ---------------------------------------------------------------------------------------------
az account management-group subscription add    --name "$RAIZ-corp"          --subscription "sub-tienda-prod"
az account management-group subscription remove --name "$RAIZ-sandbox"      --subscription "sub-laboratorio-viejo"
# Cambiar el padre de un grupo / renombrar
az account management-group update --name "$RAIZ-online" --parent "$RAIZ-landingzones" --display-name "Online (entrada pública)"

# ---------------------------------------------------------------------------------------------
# 4) AJUSTES DE LA RAÍZ (se hacen sobre el grupo raíz del tenant)
#    Requiere el rol "Hierarchy Settings Administrator" (o permisos de settings/write) en la raíz.
# ---------------------------------------------------------------------------------------------
az account management-group hierarchy-settings create \
  --name "$TENANT_ID" \
  --default-management-group "/providers/Microsoft.Management/managementGroups/$RAIZ-sandbox" \
  --require-authorization-for-group-creation true

az account management-group hierarchy-settings list --name "$TENANT_ID" -o jsonc
# Volver al comportamiento por defecto (las nuevas suscripciones caen en la raíz)
# az account management-group hierarchy-settings delete --name "$TENANT_ID"

# ---------------------------------------------------------------------------------------------
# 5) PERMISOS Y POLÍTICAS EN EL GRUPO
# ---------------------------------------------------------------------------------------------
SCOPE="/providers/Microsoft.Management/managementGroups/$RAIZ"

# Lectura para plataforma y seguridad (con PIM en la práctica)
az role assignment create --assignee-object-id "<objectId-grupo-plataforma>" --assignee-principal-type Group \
  --role "Reader" --scope "$SCOPE"

# Política: regiones permitidas en TODO ModaLima, en modo de ensayo
az policy assignment create \
  --name regiones-permitidas \
  --display-name "Regiones permitidas de ModaLima" \
  --policy e56962a6-4747-49cd-b67b-bf8b01975c4c \
  --scope "$SCOPE" \
  --enforcement-mode DoNotEnforce \
  --params '{"listOfAllowedLocations":{"value":["eastus2","centralus","global"]}}'

# Despliegue a nivel de grupo (plantillas que crean políticas, roles, etc.)
# az deployment mg create --management-group-id "$RAIZ" --location eastus2 --template-file ./gobierno.bicep

# ---------------------------------------------------------------------------------------------
# 6) ELEVAR ACCESO a la raíz (SOLO un administrador global de Entra; acto excepcional y auditable)
# ---------------------------------------------------------------------------------------------
# az rest --method post --url "/providers/Microsoft.Authorization/elevateAccess?api-version=2016-07-01"
# ... hacer lo imprescindible ...
# Revertir la elevación quitando el rol User Access Administrator en "/" (az role assignment delete --scope "/" ...)

# ---------------------------------------------------------------------------------------------
# 7) INVENTARIO con Resource Graph (más consultas en kql/kql-grupos.md)
# ---------------------------------------------------------------------------------------------
az graph query -q "
resourcecontainers
| where type =~ 'microsoft.resources/subscriptions'
| extend cadena = properties.managementGroupAncestorsChain
| project suscripcion = name, subscriptionId, grupo = tostring(cadena[0].name)
| order by grupo asc
" --first 200 -o table

# ---------------------------------------------------------------------------------------------
# 8) BORRAR un grupo (debe estar vacío: sin hijos ni suscripciones)
# ---------------------------------------------------------------------------------------------
# az account management-group delete --name "$RAIZ-desmantelado"
