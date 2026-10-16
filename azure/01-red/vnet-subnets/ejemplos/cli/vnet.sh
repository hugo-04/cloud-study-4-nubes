#!/usr/bin/env bash
# Azure: VNet con subnets por capas + NAT Gateway para salida explicita.
# Material de estudio. Revisa los flags en la version de az que tengas.
set -euo pipefail

RG=rg-estudio-red
LOC=eastus2

az account show --query "{suscripcion:name,id:id}" -o table   # confirma donde estas parado

az group create -n "$RG" -l "$LOC" --tags env=estudio owner=hugo

# VNet + primera subnet
az network vnet create -g "$RG" -n vnet-estudio \
  --address-prefixes 10.10.0.0/16 \
  --subnet-name snet-web --subnet-prefixes 10.10.0.0/24

# Resto de subnets
az network vnet subnet create -g "$RG" --vnet-name vnet-estudio -n snet-app  --address-prefixes 10.10.1.0/24
az network vnet subnet create -g "$RG" --vnet-name vnet-estudio -n snet-data --address-prefixes 10.10.2.0/24
az network vnet subnet create -g "$RG" --vnet-name vnet-estudio -n snet-pe   --address-prefixes 10.10.9.0/27

# Salida a internet explicita: NAT Gateway con IP publica fija
az network public-ip create -g "$RG" -n pip-nat --sku Standard --allocation-method Static
az network nat gateway create -g "$RG" -n natgw-estudio --public-ip-addresses pip-nat --idle-timeout 10
az network vnet subnet update -g "$RG" --vnet-name vnet-estudio -n snet-app --nat-gateway natgw-estudio

# Comprobar
az network vnet show -g "$RG" -n vnet-estudio \
  --query "{espacio:addressSpace.addressPrefixes, subnets:subnets[].{n:name,cidr:addressPrefix}}" -o json

# Limpieza (siempre al terminar)
# az group delete -n "$RG" --yes --no-wait
