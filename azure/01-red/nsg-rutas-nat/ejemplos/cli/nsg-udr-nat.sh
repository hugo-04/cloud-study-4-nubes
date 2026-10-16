#!/usr/bin/env bash
# Azure: NSG con Allow + Deny de VNet, Route Table hacia un firewall y NAT Gateway.
# Material de estudio. Requiere la VNet de ../../vnet-subnets (rg-estudio-red / vnet-estudio).
set -euo pipefail

RG=rg-estudio-red
VNET=vnet-estudio

# 1) NSG de la subnet de datos: solo la subnet de aplicacion llega al 1433
az network nsg create -g "$RG" -n nsg-data

az network nsg rule create -g "$RG" --nsg-name nsg-data -n allow-app-to-sql \
  --priority 100 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes 10.10.1.0/24 --destination-port-ranges 1433

az network nsg rule create -g "$RG" --nsg-name nsg-data -n deny-vnet-inbound \
  --priority 4000 --direction Inbound --access Deny --protocol '*' \
  --source-address-prefixes VirtualNetwork --destination-port-ranges '*'

az network vnet subnet update -g "$RG" --vnet-name "$VNET" -n snet-data \
  --network-security-group nsg-data

# 2) Route Table: toda la salida por un firewall (IP privada de ejemplo)
az network route-table create -g "$RG" -n rt-app --disable-bgp-route-propagation true
az network route-table route create -g "$RG" --route-table-name rt-app -n default-via-fw \
  --address-prefix 0.0.0.0/0 --next-hop-type VirtualAppliance --next-hop-ip-address 10.10.250.4
# az network vnet subnet update -g "$RG" --vnet-name "$VNET" -n snet-app --route-table rt-app
#   (descomenta solo si existe de verdad un firewall en 10.10.250.4; si no, la salida deja de funcionar)

# 3) Comprobar lo que de verdad aplica
az network nsg rule list -g "$RG" --nsg-name nsg-data -o table
az network route-table route list -g "$RG" --route-table-name rt-app -o table

# Limpieza: az group delete -n "$RG" --yes --no-wait
