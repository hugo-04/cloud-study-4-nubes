#!/usr/bin/env bash
# Azure Managed Redis con Azure CLI: crear, asegurar, conectar y diagnosticar.
# Requisitos: az login y la extensión de Redis Enterprise (az extension add -n redisenterprise si te lo pide).
# Azure Managed Redis usa el proveedor Microsoft.Cache/redisEnterprise, por eso los comandos son "az redisenterprise".
set -euo pipefail

# ---------------------------------------------------------------- Variables
RG="rg-estudio-redis"
LOC="eastus2"
CACHE="amr-modalima-demo01"        # nombre del recurso (único por región)
SKU="Balanced_B5"                  # Familia_Tamaño: Balanced_B0..B1000, ComputeOptimized_X3..X700, MemoryOptimized_M10..M2000, FlashOptimized_A250..A4500
APP_PRINCIPAL_ID="00000000-0000-0000-0000-0000000000a1"   # identidad administrada de la API de pedidos

az group create -n "$RG" -l "$LOC" -o none

# ---------------------------------------------------------------- 1. Crear la instancia
# Política de clúster y módulos NO se pueden cambiar después. OSSCluster = mejor rendimiento (cliente con soporte de clúster);
# EnterpriseCluster = un solo endpoint y cualquier cliente (necesaria para RediSearch, que además exige NoEviction).
az redisenterprise create \
  --cluster-name "$CACHE" \
  --resource-group "$RG" \
  --location "$LOC" \
  --sku "$SKU" \
  --high-availability Enabled \
  --clustering-policy OSSCluster \
  --eviction-policy VolatileLRU \
  --client-protocol Encrypted \
  --minimum-tls-version 1.2 \
  --access-keys-auth Disabled \
  --public-network-access Disabled \
  --port 10000

# Con módulos (solo al crear): --modules name=RedisJSON --modules name=RediSearch
# Con persistencia RDB cada hora: --persistence rdb-enabled=true rdb-frequency=1h   (no compatible con geo-replicación; verifica la sintaxis con -h)

az redisenterprise show --cluster-name "$CACHE" --resource-group "$RG" \
  --query "{nombre:name, host:hostName, sku:sku.name, estado:resourceState, version:redisVersion}" -o table

# ---------------------------------------------------------------- 2. Acceso de datos con Entra ID
# Asigna la política de acceso a la identidad de la aplicación (portal: Autenticación → Microsoft Entra → + Seleccionar miembro).
# En CLI (vista previa) revisa los parámetros con:
#   az redisenterprise database access-policy-assignment create -h
# o usa Terraform: azurerm_managed_redis_access_policy_assignment (ver ejemplos/terraform).
echo "Identidad a autorizar: $APP_PRINCIPAL_ID"

# Prueba de conexión con tu identidad (az login) y Entra ID: envía un PING
az redisenterprise test-connection --name "$CACHE" --resource-group "$RG" --auth entra || true

# Claves de acceso (solo si NO las desactivaste; evita usarlas)
# az redisenterprise database list-keys --cluster-name "$CACHE" --resource-group "$RG"

# ---------------------------------------------------------------- 3. Red privada
ID_CACHE=$(az redisenterprise show --cluster-name "$CACHE" --resource-group "$RG" --query id -o tsv)

# Private Endpoint (subrecurso redisEnterprise) y zona DNS privatelink.redis.azure.net: ver el Terraform. Con CLI:
# az network private-endpoint create -g "$RG" -n pe-redis --vnet-name vnet-redis --subnet snet-private-endpoints \
#   --private-connection-resource-id "$ID_CACHE" --group-id redisEnterprise --connection-name psc-redis
# az network private-dns zone create -g "$RG" -n privatelink.redis.azure.net
# az network private-endpoint dns-zone-group create -g "$RG" --endpoint-name pe-redis -n zona-redis \
#   --private-dns-zone privatelink.redis.azure.net --zone-name redis
# Desde dentro de la red: nslookup <cache>.<region>.redis.azure.net  → debe resolver a una IP privada.

# ---------------------------------------------------------------- 4. Operación
# Vaciar la base (¡borra todos los datos!; en geo-replicación vacía TODAS las instancias del grupo)
# az redisenterprise database flush --cluster-name "$CACHE" --resource-group "$RG" --no-wait

# Escalar: cambia a una SKU mayor (no se puede reducir); mejor con IaC y en ventana de mantenimiento.

# ---------------------------------------------------------------- 5. Diagnóstico
LAW_ID=$(az monitor log-analytics workspace create -g "$RG" -n log-redis-demo -l "$LOC" --query id -o tsv)
az monitor diagnostic-settings create --name diag-redis --resource "$ID_CACHE" --workspace "$LAW_ID" \
  --logs '[{"category":"ConnectionEvents","enabled":true}]' \
  --metrics '[{"category":"AllMetrics","enabled":true}]'

# Métricas rápidas (última hora)
for METRICA in usedmemorypercentage serverLoad connectedclients evictedkeys; do
  echo "== $METRICA"
  az monitor metrics list --resource "$ID_CACHE" --metric "$METRICA" --interval PT5M \
    --aggregation Maximum --offset 1h -o table
done

echo "Host: $(az redisenterprise show --cluster-name "$CACHE" --resource-group "$RG" --query hostName -o tsv):10000 (TLS)"
