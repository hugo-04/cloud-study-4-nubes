#!/usr/bin/env bash
# Verifica que los servicios de la tienda NO tienen acceso público y que su Private Endpoint está aprobado.
# Uso: ./verificar-privado.sh <grupo-datos> <sql> <boveda> <cuenta> <espacio-sb>
set -uo pipefail
RG="${1:?grupo de recursos}"; SQL="${2:?servidor sql}"; KV="${3:?boveda}"; ST="${4:?cuenta de almacenamiento}"; SB="${5:?espacio de service bus}"

estado() { printf '%-34s %s\n' "$1" "$2"; }

estado "SQL acceso público"        "$(az sql server show -g "$RG" -n "$SQL" --query publicNetworkAccess -o tsv)"
estado "Key Vault acceso público"  "$(az keyvault show -n "$KV" --query properties.publicNetworkAccess -o tsv)"
estado "Storage acceso público"    "$(az storage account show -g "$RG" -n "$ST" --query publicNetworkAccess -o tsv)"
estado "Storage claves permitidas" "$(az storage account show -g "$RG" -n "$ST" --query allowSharedKeyAccess -o tsv)"
estado "Service Bus acceso público" "$(az servicebus namespace show -g "$RG" -n "$SB" --query publicNetworkAccess -o tsv)"
estado "Service Bus clave local"   "$(az servicebus namespace show -g "$RG" -n "$SB" --query disableLocalAuth -o tsv)"

echo
echo "Private Endpoints y su estado de conexión:"
az network private-endpoint list -g "$RG" \
  --query "[].{endpoint:name, estado:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status, subrecurso:privateLinkServiceConnections[0].groupIds[0]}" -o table

echo
echo "Enlaces de las zonas DNS privadas a la VNet:"
for zona in $(az network private-dns zone list -g "$RG" --query "[].name" -o tsv); do
  printf '%s: ' "$zona"
  az network private-dns link vnet list -g "$RG" -z "$zona" --query "[].{vnet:virtualNetwork.id}" -o tsv | tr '\n' ' '
  echo
done

echo
echo "Desde un pod del clúster (la resolución debe devolver una IP PRIVADA):"
echo "  kubectl run t --rm -it --image=busybox --restart=Never -- nslookup $SQL.database.windows.net"
