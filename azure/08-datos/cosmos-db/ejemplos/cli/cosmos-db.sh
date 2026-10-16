#!/usr/bin/env bash
# Azure Cosmos DB (API para NoSQL) con Azure CLI: crear, asegurar, operar y diagnosticar.
# Requisitos: az login. Reemplaza los valores de la sección "Variables".
set -euo pipefail

# ---------------------------------------------------------------- Variables
RG="rg-estudio-cosmos"
LOC="eastus2"
LOC2="centralus"
CUENTA="cosmos-modalima-demo01"    # único global, minúsculas, 3-44 caracteres
BASE="pedidos-db"
APP_PRINCIPAL_ID="00000000-0000-0000-0000-0000000000a1"   # identidad administrada de la API de pedidos
REPORTES_PRINCIPAL_ID="00000000-0000-0000-0000-0000000000b2"
DIR="$(cd "$(dirname "$0")" && pwd)"

# ---------------------------------------------------------------- 1. Cuenta
az group create -n "$RG" -l "$LOC" -o none

# Producción: dos regiones con zonas, conmutación automática, copia continua y SIN claves
az cosmosdb create -g "$RG" -n "$CUENTA" \
  --locations regionName="$LOC" failoverPriority=0 isZoneRedundant=True \
  --locations regionName="$LOC2" failoverPriority=1 isZoneRedundant=True \
  --default-consistency-level Session \
  --enable-automatic-failover true \
  --backup-policy-type Continuous --continuous-tier Continuous30Days \
  --disable-key-based-metadata-write-access true \
  --minimal-tls-version Tls12 \
  --public-network-access DISABLED

# Desarrollo (serverless, una región): añade --capabilities EnableServerless y quita las opciones de regiones/HA.
# Capa gratuita (1 000 RU/s + 25 GB, una por suscripción): --enable-free-tier true

# Desactivar las claves (solo Entra ID + RBAC de datos)
az resource update -g "$RG" -n "$CUENTA" --resource-type "Microsoft.DocumentDB/databaseAccounts" \
  --set properties.disableLocalAuth=true

# ---------------------------------------------------------------- 2. Base de datos y contenedores
az cosmosdb sql database create -g "$RG" -a "$CUENTA" -n "$BASE"

# Contenedor de pedidos: clave /clienteId, autoscale hasta 10 000 RU/s, política de indexación desde archivo.
# --ttl -1 = TTL activado sin vencimiento por defecto: solo expiran los documentos con su propia propiedad "ttl".
az cosmosdb sql container create -g "$RG" -a "$CUENTA" -d "$BASE" -n pedidos \
  --partition-key-path "/clienteId" \
  --max-throughput 10000 \
  --ttl -1 \
  --idx @"$DIR/../json/politica-indexado.json" \
  --unique-key-policy '{"uniqueKeys":[{"paths":["/referenciaExterna"]}]}'

# Carritos con TTL de 7 días
az cosmosdb sql container create -g "$RG" -a "$CUENTA" -d "$BASE" -n carritos \
  --partition-key-path "/clienteId" --max-throughput 4000 --ttl 604800

# Arrendamientos para el change feed
az cosmosdb sql container create -g "$RG" -a "$CUENTA" -d "$BASE" -n leases \
  --partition-key-path "/id" --max-throughput 1000

# Clave jerárquica (multi-inquilino): hasta 3 niveles
# az cosmosdb sql container create ... --partition-key-path "/tenantId" "/clienteId" --partition-key-version 2   # verifica la sintaxis vigente

# ---------------------------------------------------------------- 3. Rendimiento
az cosmosdb sql container throughput show -g "$RG" -a "$CUENTA" -d "$BASE" -n pedidos
# Subir el máximo de autoscale (campaña):
az cosmosdb sql container throughput update -g "$RG" -a "$CUENTA" -d "$BASE" -n pedidos --max-throughput 20000
# Pasar de manual a autoscale (o al revés):
# az cosmosdb sql container throughput migrate -g "$RG" -a "$CUENTA" -d "$BASE" -n pedidos -t autoscale

# ---------------------------------------------------------------- 4. RBAC de datos (no son roles de Azure RBAC)
ID_CUENTA=$(az cosmosdb show -g "$RG" -n "$CUENTA" --query id -o tsv)

# Roles integrados: lector ...0001, colaborador ...0002
az cosmosdb sql role definition list -g "$RG" -a "$CUENTA" --query "[].{id:name, nombre:roleName}" -o table

az cosmosdb sql role assignment create -g "$RG" -a "$CUENTA" \
  --role-definition-id 00000000-0000-0000-0000-000000000002 \
  --principal-id "$APP_PRINCIPAL_ID" \
  --scope "${ID_CUENTA}/dbs/${BASE}"

az cosmosdb sql role assignment create -g "$RG" -a "$CUENTA" \
  --role-definition-id 00000000-0000-0000-0000-000000000001 \
  --principal-id "$REPORTES_PRINCIPAL_ID" \
  --scope "${ID_CUENTA}/dbs/${BASE}"

# Rol personalizado sin borrado
az cosmosdb sql role definition create -g "$RG" -a "$CUENTA" --body @"$DIR/../json/rol-sin-borrado.json"

az cosmosdb sql role assignment list -g "$RG" -a "$CUENTA" -o table

# ---------------------------------------------------------------- 5. Red privada
# Zona DNS privada y Private Endpoint (subrecurso Sql): ver el Terraform. Con CLI:
# az network private-endpoint create -g "$RG" -n pe-cosmos-sql --vnet-name vnet-cosmos --subnet snet-private-endpoints \
#   --private-connection-resource-id "$ID_CUENTA" --group-id Sql --connection-name psc-cosmos
# Recuerda: modo Directo del SDK usa además los puertos 10250-10255 hacia el endpoint privado.

# ---------------------------------------------------------------- 6. Regiones y conmutación
az cosmosdb show -g "$RG" -n "$CUENTA" --query "locations[].{region:locationName, prioridad:failoverPriority}" -o table
# Cambiar prioridades (la de prioridad 0 es la región de escritura):
# az cosmosdb failover-priority-change -g "$RG" -n "$CUENTA" --failover-policies "${LOC2}=0" "${LOC}=1"
# Simulacro de conmutación: hazlo en una cuenta de pruebas.

# ---------------------------------------------------------------- 7. Copias y restauración (copia continua)
# Restaurar a un instante en una CUENTA NUEVA (por ejemplo, antes de un borrado accidental)
# az cosmosdb restore -g "$RG" -n "${CUENTA}-restaurada" --source-database-account-name "$CUENTA" \
#   --restore-timestamp "2026-10-16T14:00:00Z" --location "$LOC"
az cosmosdb restorable-database-account list --query "[?name=='$CUENTA'].{id:name, creada:creationTime}" -o table || true

# ---------------------------------------------------------------- 8. Diagnóstico
LAW_ID=$(az monitor log-analytics workspace create -g "$RG" -n log-cosmos-demo -l "$LOC" --query id -o tsv)
az monitor diagnostic-settings create --name diag-cosmos --resource "$ID_CUENTA" --workspace "$LAW_ID" \
  --export-to-resource-specific true \
  --logs '[{"category":"DataPlaneRequests","enabled":true},{"category":"QueryRuntimeStatistics","enabled":true},{"category":"PartitionKeyStatistics","enabled":true},{"category":"PartitionKeyRUConsumption","enabled":true},{"category":"ControlPlaneRequests","enabled":true}]' \
  --metrics '[{"category":"Requests","enabled":true}]'

# Métricas rápidas: consumo normalizado de RU de la última hora
az monitor metrics list --resource "$ID_CUENTA" --metric NormalizedRUConsumption --interval PT5M \
  --aggregation Maximum --offset 1h -o table

echo "Listo. Conecta con DefaultAzureCredential y el endpoint: $(az cosmosdb show -g "$RG" -n "$CUENTA" --query documentEndpoint -o tsv)"
