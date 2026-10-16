#!/usr/bin/env bash
# Azure Files por CLI: crear, proteger, montar, instantáneas, recuperar y diagnosticar.
# Ejecuta por secciones. Los comandos de montaje se ejecutan en la VM/servidor cliente, no donde corres 'az'.
set -euo pipefail

RG=rg-estudio-files
ST=stfsmbXXXXXX                  # salida "cuenta_smb" de Terraform
SHARE=contabilidad
LOC=eastus2

echo "== 1) Crear cuenta premium y share (equivalente a lo que hace Terraform) =="
# az storage account create -g "$RG" -n "$ST" -l "$LOC" --kind FileStorage --sku Premium_ZRS \
#   --min-tls-version TLS1_2 --allow-blob-public-access false --allow-shared-key-access false
# az storage share-rm create -g "$RG" --storage-account "$ST" -n "$SHARE" --quota 1024 --enabled-protocols SMB

echo "== 2) Estado del share (cuota, protocolo, nivel) =="
az storage share-rm show -g "$RG" --storage-account "$ST" -n "$SHARE" \
  --query '{cuota:shareQuota,protocolo:enabledProtocols,nivel:accessTier,uso:shareUsageBytes}' -o table

echo "== 3) Cambiar la cuota (en premium sube el rendimiento y el costo) =="
az storage share-rm update -g "$RG" --storage-account "$ST" -n "$SHARE" --quota 2048 -o none

echo "== 4) Eliminación temporal (soft delete) de shares: 7 días =="
az storage account file-service-properties update -g "$RG" --account-name "$ST" \
  --enable-delete-retention true --delete-retention-days 7 -o none

echo "== 5) Identidad: habilitar Microsoft Entra Kerberos y dar rol de share =="
az storage account update -g "$RG" -n "$ST" --enable-files-aadkerb true -o none
SCOPE=$(az storage account show -g "$RG" -n "$ST" --query id -o tsv)/fileServices/default/fileshares/$SHARE
# az role assignment create --assignee <objectId-del-grupo> --role "Storage File Data SMB Share Contributor" --scope "$SCOPE"

echo "== 6) Subir y listar por REST con tu identidad (rol de datos requerido) =="
echo 'hola' > /tmp/hola.txt
az storage file upload --account-name "$ST" --share-name "$SHARE" --source /tmp/hola.txt --path prueba/hola.txt \
  --auth-mode login --enable-file-backup-request-intent -o none
az storage file list --account-name "$ST" --share-name "$SHARE" --path prueba \
  --auth-mode login --enable-file-backup-request-intent -o table

echo "== 7) Instantáneas: crear, listar, borrar =="
SNAP=$(az storage share snapshot --account-name "$ST" -n "$SHARE" --auth-mode login --query snapshot -o tsv)
echo "instantánea=$SNAP"
az storage share list --account-name "$ST" --include-snapshot --auth-mode login \
  --query "[?name=='$SHARE'].{nombre:name,snapshot:snapshot}" -o table
# az storage share delete --account-name "$ST" -n "$SHARE" --snapshot "$SNAP" --auth-mode login

echo "== 8) Recuperar un archivo desde la instantánea (descargar de la instantánea y volver a subir) =="
az storage file download --account-name "$ST" --share-name "$SHARE" --path prueba/hola.txt --snapshot "$SNAP" \
  --dest /tmp/hola-recuperado.txt --auth-mode login --enable-file-backup-request-intent -o none
az storage file upload --account-name "$ST" --share-name "$SHARE" --source /tmp/hola-recuperado.txt --path prueba/hola.txt \
  --auth-mode login --enable-file-backup-request-intent -o none

echo "== 9) Recuperar un SHARE borrado (soft delete) =="
# az storage share-rm list -g "$RG" --storage-account "$ST" --include-deleted -o table
# az storage share-rm restore -g "$RG" --storage-account "$ST" --name "$SHARE" --deleted-version <version> 

echo "== 10) Conectividad: ¿llega el puerto 445 desde aquí? ¿resuelve a IP privada? =="
nslookup "$ST.file.core.windows.net" || true
(command -v nc >/dev/null && nc -zv -w 5 "$ST.file.core.windows.net" 445) || echo "445 no alcanzable desde este equipo (normal fuera de Azure/VPN)"

echo "== 11) MONTAR en Linux (se ejecuta en la VM; requiere cifs-utils) =="
cat <<'MONTAJE'
# SMB con identidad (Kerberos; el equipo debe estar unido al dominio/Entra y tener ticket):
#   sudo mkdir -p /mnt/contabilidad
#   sudo mount -t cifs //$ST.file.core.windows.net/contabilidad /mnt/contabilidad \
#     -o sec=krb5,cruid=$(id -u),uid=$(id -u),gid=$(id -g),serverino,nosharesock,actimeo=30,mfsymlinks,vers=3.1.1
#
# SMB con clave de la cuenta (SOLO pruebas; no funciona si shared_access_key_enabled=false):
#   sudo mount -t cifs //$ST.file.core.windows.net/contabilidad /mnt/contabilidad \
#     -o username=$ST,password="$CLAVE",serverino,nosharesock,actimeo=30,mfsymlinks,vers=3.1.1,dir_mode=0770,file_mode=0660
#
# NFS 4.1 (cuenta aparte, solo por red privada o service endpoint):
#   sudo mkdir -p /mnt/datos
#   sudo mount -t nfs $STNFS.file.core.windows.net:/$STNFS/datos-compartidos /mnt/datos \
#     -o vers=4,minorversion=1,sec=sys,nconnect=4
#
# Persistir en /etc/fstab (añade _netdev para esperar a la red):
#   //$ST.file.core.windows.net/contabilidad /mnt/contabilidad cifs _netdev,nofail,sec=krb5,vers=3.1.1,serverino 0 0
MONTAJE

echo "== 12) Métricas útiles (latencia, transacciones, capacidad) =="
az monitor metrics list --resource "$(az storage account show -g "$RG" -n "$ST" --query id -o tsv)/fileServices/default" \
  --metric Transactions SuccessE2ELatency FileCapacity --interval PT5M --aggregation Average Total -o table || true

echo "== 13) Limpieza de la práctica =="
# az group delete -n "$RG" --yes --no-wait
