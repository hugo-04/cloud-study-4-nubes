#!/usr/bin/env bash
# Data Lake Gen2 por CLI: crear lago, directorios, ACL (recursivas), mover, migrar a HNS y diagnosticar.
# Ejecuta por secciones. Con identidad (--auth-mode login) necesitas rol de datos o ACL en la ruta.
set -euo pipefail

RG=rg-estudio-lago
ST=stlagoXXXXXX                 # salida "cuenta" de Terraform
LOC=eastus2
GRUPO_ING=00000000-0000-0000-0000-0000000000a1      # object id de un GRUPO de Entra ID
GRUPO_ANA=00000000-0000-0000-0000-0000000000a2

echo "== 1) Crear la cuenta con HNS (decisión de diseño) y un sistema de archivos =="
# az storage account create -g "$RG" -n "$ST" -l "$LOC" --sku Standard_ZRS --kind StorageV2 \
#   --enable-hierarchical-namespace true --min-tls-version TLS1_2 --allow-blob-public-access false --allow-shared-key-access false
az storage fs create --account-name "$ST" -n silver --auth-mode login -o none

echo "== 2) Directorios y archivos =="
az storage fs directory create --account-name "$ST" -f silver -n ventas/anio=2026/mes=10/dia=16 --auth-mode login -o none
echo '{"sku":"A1","precio":10}' > /tmp/venta.ndjson
az storage fs file upload --account-name "$ST" -f silver -s /tmp/venta.ndjson -p ventas/anio=2026/mes=10/dia=16/part-0001.ndjson --auth-mode login -o none
az storage fs file list --account-name "$ST" -f silver --path ventas --recursive true --auth-mode login \
  --query '[].{ruta:name,directorio:isDirectory,bytes:contentLength}' -o table

echo "== 3) Ver las ACL de una ruta =="
az storage fs access show --account-name "$ST" -f silver -p ventas --auth-mode login -o jsonc

echo "== 4) Dar a un GRUPO lectura sobre el árbol (ACL de acceso + POR DEFECTO) de forma RECURSIVA =="
# 'update-recursive' agrega/modifica solo esas entradas; 'set-recursive' REEMPLAZA todo (peligroso)
az storage fs access update-recursive --account-name "$ST" -f silver -p ventas --auth-mode login \
  --acl "group:$GRUPO_ANA:r-x,default:group:$GRUPO_ANA:r-x"

echo "== 5) Los grupos necesitan 'x' en la raíz del sistema de archivos para llegar =="
az storage fs access update-recursive --account-name "$ST" -f silver -p / --auth-mode login \
  --acl "group:$GRUPO_ANA:--x,group:$GRUPO_ING:--x" || echo "(si falla en la raíz, usa: az storage fs access set -f silver -p / ... sin recursión)"

echo "== 6) Escritura para el grupo de ingeniería (rwx) =="
az storage fs access update-recursive --account-name "$ST" -f silver -p ventas --auth-mode login \
  --acl "group:$GRUPO_ING:rwx,default:group:$GRUPO_ING:rwx"

echo "== 7) Renombrar/mover una carpeta (UNA operación atómica, sin copiar datos) =="
az storage fs directory move --account-name "$ST" -f silver -n ventas/anio=2026/mes=10/dia=16 \
  --new-directory silver/ventas/anio=2026/mes=10/dia=16-reproceso --auth-mode login -o none || true

echo "== 8) Publicar un archivo con _tmp y mover (patrón de publicación atómica) =="
az storage fs file upload --account-name "$ST" -f silver -s /tmp/venta.ndjson -p _tmp/lote-1.ndjson --auth-mode login -o none
az storage fs file move --account-name "$ST" -f silver -p _tmp/lote-1.ndjson \
  --new-path silver/ventas/anio=2026/mes=10/dia=17/part-0001.ndjson --auth-mode login -o none || true

echo "== 9) Migración de una cuenta existente a HNS: VALIDAR primero, luego actualizar (camino de ida) =="
# az storage account hns-migration start -g "$RG" -n "$ST" --type validation
# az storage account hns-migration start -g "$RG" -n "$ST" --type upgrade --no-wait

echo "== 10) SFTP (solo si un socio lo necesita) =="
# az storage account update -g "$RG" -n "$ST" --enable-sftp true --enable-local-user true
# az storage account local-user create -g "$RG" --account-name "$ST" -n cafeandino --home-directory landing/socios/cafeandino \
#   --permission-scope permissions=rwlc service=blob resource-name=landing --has-ssh-key true --ssh-authorized-key key="$(cat ~/.ssh/id_rsa.pub)"
# sftp cuenta.cafeandino@cuenta.blob.core.windows.net

echo "== 11) URIs para Spark/Databricks/Synapse =="
echo "abfss://silver@$ST.dfs.core.windows.net/ventas/anio=2026/mes=10/"

echo "== 12) Probar permisos como OTRA identidad (¿puede el grupo listar y leer?) =="
# az login --service-principal ...   # o con un usuario miembro del grupo
# az storage fs file list --account-name "$ST" -f silver --path ventas --auth-mode login

echo "== 13) Limpieza de la práctica =="
# az group delete -n "$RG" --yes --no-wait
