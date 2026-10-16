#!/usr/bin/env bash
# Azure: hub-and-spoke minimo con peering en ambos sentidos.
# Material de estudio.
set -euo pipefail

RG=rg-estudio-hub
LOC=eastus2

az group create -n "$RG" -l "$LOC"

az network vnet create -g "$RG" -n vnet-hub   --address-prefixes 10.50.0.0/16 \
  --subnet-name snet-shared --subnet-prefixes 10.50.1.0/24
az network vnet create -g "$RG" -n vnet-spoke --address-prefixes 10.60.0.0/16 \
  --subnet-name snet-app    --subnet-prefixes 10.60.1.0/24

# Hay que crear LOS DOS sentidos. Sin el segundo el estado queda "Initiated".
az network vnet peering create -g "$RG" -n hub-to-spoke \
  --vnet-name vnet-hub --remote-vnet vnet-spoke \
  --allow-vnet-access --allow-forwarded-traffic
# Si el hub tiene un VPN/ExpressRoute Gateway, agrega: --allow-gateway-transit

az network vnet peering create -g "$RG" -n spoke-to-hub \
  --vnet-name vnet-spoke --remote-vnet vnet-hub \
  --allow-vnet-access --allow-forwarded-traffic
# Para usar el gateway del hub, agrega: --use-remote-gateways

az network vnet peering list -g "$RG" --vnet-name vnet-hub \
  --query "[].{n:name,estado:peeringState}" -o table
az network vnet peering list -g "$RG" --vnet-name vnet-spoke \
  --query "[].{n:name,estado:peeringState}" -o table

# Limpieza: az group delete -n "$RG" --yes --no-wait
