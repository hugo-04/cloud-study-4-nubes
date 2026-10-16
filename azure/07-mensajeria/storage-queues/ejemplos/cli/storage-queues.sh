#!/usr/bin/env bash
# Storage Queues por CLI: cuenta, colas, mensajes (enviar/ver/recibir/borrar/actualizar), métricas.
# Ejecuta por secciones. Requiere: az login. Con --auth-mode login se usan tus roles de datos (sin claves).
set -euo pipefail

RG=rg-estudio-storagequeues
ST=stqmodalimaXXXXXX               # salida "cuenta" de Terraform
Q=tareas-demo
LOC=eastus2

echo "== 1) Cuenta sin claves =="
# az storage account create -g "$RG" -n "$ST" -l "$LOC" --sku Standard_ZRS --min-tls-version TLS1_2 \
#   --allow-blob-public-access false --allow-shared-key-access false
az storage account show -g "$RG" -n "$ST" \
  --query '{sinClaves:allowSharedKeyAccess,tls:minimumTlsVersion,publico:publicNetworkAccess}' -o table

echo "== 2) Crear colas =="
az storage queue create --account-name "$ST" -n "$Q" --auth-mode login -o none
az storage queue create --account-name "$ST" -n "${Q}-poison" --auth-mode login -o none
az storage queue list --account-name "$ST" --auth-mode login --query '[].name' -o tsv

echo "== 3) Enviar mensajes (TTL 2 días; el segundo, diferido 60 s) =="
az storage message put --account-name "$ST" -q "$Q" --auth-mode login --content '{"v":1,"productoId":"p-100"}' --time-to-live 172800 -o none
az storage message put --account-name "$ST" -q "$Q" --auth-mode login --content '{"v":1,"productoId":"p-101"}' --visibility-timeout 60 -o none

echo "== 4) Ver sin consumir (peek) =="
az storage message peek --account-name "$ST" -q "$Q" --auth-mode login --num-messages 5 -o table

echo "== 5) Recibir (hace invisible 30 s), actualizar y borrar =="
MSG=$(az storage message get --account-name "$ST" -q "$Q" --auth-mode login --visibility-timeout 30 --num-messages 1 -o json)
ID=$(echo "$MSG" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d[0]["id"] if d else "")')
POP=$(echo "$MSG" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d[0]["popReceipt"] if d else "")')
if [ -n "$ID" ]; then
  echo "Mensaje $ID (dequeueCount $(echo "$MSG" | python3 -c 'import sys,json; print(json.load(sys.stdin)[0]["dequeueCount"])'))"
  # alargar la invisibilidad (trabajo largo / retroceso)
  az storage message update --account-name "$ST" -q "$Q" --auth-mode login --id "$ID" --pop-receipt "$POP" \
    --visibility-timeout 120 --content '{"v":1,"productoId":"p-100","intento":2}' -o none || true
  # borrar (usa el popReceipt MÁS RECIENTE; si actualizaste, vuelve a leerlo de la respuesta del update)
  # az storage message delete --account-name "$ST" -q "$Q" --auth-mode login --id "$ID" --pop-receipt "$NUEVO_POP"
fi

echo "== 6) Cuántos mensajes hay (aproximado) =="
az storage queue stats --account-name "$ST" --auth-mode login 2>/dev/null || true
az storage queue metadata show --account-name "$ST" -n "$Q" --auth-mode login --query 'approximateMessageCount' -o tsv 2>/dev/null || true

echo "== 7) Vaciar la cola de pruebas =="
# az storage message clear --account-name "$ST" -q "$Q" --auth-mode login

echo "== 8) Roles (ver quién puede qué) =="
SCOPE=$(az storage account show -g "$RG" -n "$ST" --query id -o tsv)
az role assignment list --scope "$SCOPE" --query "[?contains(roleDefinitionName,'Queue')].{rol:roleDefinitionName,principal:principalName}" -o table

echo "== 9) Limpieza =="
# az storage queue delete --account-name "$ST" -n "$Q" --auth-mode login
echo "ok"
