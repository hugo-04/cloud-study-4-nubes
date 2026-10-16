#!/usr/bin/env bash
# Azure: Storage con Private Endpoint + zona DNS privada + cierre del acceso publico.
# Material de estudio. Requiere la VNet de ../../vnet-subnets (rg-estudio-red / vnet-estudio / snet-pe).
set -euo pipefail

RG=rg-estudio-red
VNET=vnet-estudio
LOC=eastus2
ST=stestudio$RANDOM$RANDOM          # nombre unico global: minusculas y numeros, 3-24 caracteres
ZONA=privatelink.blob.core.windows.net

az account show --query name -o tsv

# 0) Storage (por ahora con acceso publico para poder probar despues)
az storage account create -g "$RG" -n "$ST" -l "$LOC" --sku Standard_LRS \
  --min-tls-version TLS1_2 --allow-blob-public-access false

STID=$(az storage account show -g "$RG" -n "$ST" --query id -o tsv)

# 1) Private Endpoint hacia el sub-recurso blob
az network private-endpoint create -g "$RG" -n pe-st-blob \
  --vnet-name "$VNET" --subnet snet-pe \
  --private-connection-resource-id "$STID" \
  --group-id blob --connection-name conn-st-blob

# 2) Zona DNS privada y enlace a la VNet
az network private-dns zone create -g "$RG" -n "$ZONA"
az network private-dns link vnet create -g "$RG" -n "link-$VNET" \
  --zone-name "$ZONA" --virtual-network "$VNET" --registration-enabled false

# 3) Zone group: crea y mantiene el registro A del endpoint
az network private-endpoint dns-zone-group create -g "$RG" \
  --endpoint-name pe-st-blob -n default \
  --private-dns-zone "$ZONA" --zone-name blob

# 4) Verificar la conexion y el DNS (el nslookup debe hacerse DESDE una maquina dentro de la VNet)
az network private-endpoint show -g "$RG" -n pe-st-blob \
  --query "privateLinkServiceConnections[0].privateLinkServiceConnectionState.status" -o tsv
az network private-dns record-set a list -g "$RG" -z "$ZONA" -o table
echo "Dentro de la VNet ejecuta: nslookup $ST.blob.core.windows.net   (esperado: 10.10.9.x)"

# 5) SOLO despues de verificar, cerrar el acceso publico
# az storage account update -g "$RG" -n "$ST" --public-network-access Disabled

# Limpieza: az group delete -n "$RG" --yes --no-wait
