#!/usr/bin/env bash
# Azure: comandos de diagnostico de red con Network Watcher.
# Material de estudio. Reemplaza las variables por tus valores.
set -euo pipefail

RG=rg-estudio-red
VM=vm-test
NIC=nic-vm-test
ORIGEN=10.10.1.4
DESTINO=10.10.2.4
PUERTO=1433

echo "== 1) Rutas efectivas de la NIC de origen =="
az network nic show-effective-route-table -g "$RG" -n "$NIC" -o table

echo "== 2) Reglas de NSG efectivas =="
az network nic list-effective-nsg -g "$RG" --name "$NIC" -o json | head -60

echo "== 3) IP flow verify: que regla permite o niega este flujo =="
az network watcher test-ip-flow -g "$RG" --vm "$VM" \
  --direction Outbound --protocol TCP \
  --local "$ORIGEN:50000" --remote "$DESTINO:$PUERTO"

echo "== 4) Siguiente salto =="
az network watcher show-next-hop -g "$RG" --vm "$VM" \
  --source-ip "$ORIGEN" --dest-ip "$DESTINO"

echo "== 5) Connection troubleshoot (requiere la extension del agente de Network Watcher en la VM) =="
az network watcher test-connectivity -g "$RG" --source-resource "$VM" \
  --dest-address "$DESTINO" --dest-port "$PUERTO"

echo "== 6) DNS: ejecutar DENTRO de la VNet =="
echo "nslookup nombre-del-servicio"
echo "nc -zv $DESTINO $PUERTO"
echo "curl -vk https://nombre-del-servicio/health"
echo "openssl s_client -connect nombre-del-servicio:443 -servername nombre-del-servicio </dev/null | head -20"
