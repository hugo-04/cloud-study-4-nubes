#!/usr/bin/env bash
# PostgreSQL Flexible Server por CLI: servidor solo-Entra, red, parámetros, HA, réplicas, PITR y conexión con token.
# Ejecuta por secciones. Requiere: az login. Los parámetros varían por versión del CLI: revisa --help.
set -euo pipefail

RG=rg-estudio-postgres
PG=pg-modalima-XXXXXX               # salida "servidor" de Terraform (sin .postgres.database.azure.com)
DB=pedidos
LOC=eastus2

echo "== 1) Crear el servidor (acceso privado en una subred delegada, Entra ID, HA entre zonas) =="
# az postgres flexible-server create -g "$RG" -n "$PG" -l "$LOC" --version 17 \
#   --tier GeneralPurpose --sku-name Standard_D4ds_v5 --storage-size 256 --storage-auto-grow Enabled \
#   --high-availability ZoneRedundant --zone 1 --standby-zone 2 \
#   --vnet vnet-postgres --subnet snet-postgres --private-dns-zone modalima.private.postgres.database.azure.com \
#   --backup-retention 14 --geo-redundant-backup Enabled \
#   --microsoft-entra-auth Enabled --password-auth Disabled
az postgres flexible-server show -g "$RG" -n "$PG" \
  --query '{estado:state,version:version,sku:sku.name,ha:highAvailability.mode,red:network.publicNetworkAccess,almacenamientoGB:storage.storageSizeGb,pitrDias:backup.backupRetentionDays}' -o table

echo "== 2) Administrador de Entra (un grupo) =="
# az postgres flexible-server microsoft-entra-admin create -g "$RG" -s "$PG" -u DBAdmins -i <OBJECT_ID_DEL_GRUPO> -t Group
az postgres flexible-server microsoft-entra-admin list -g "$RG" -s "$PG" -o table 2>/dev/null || true

echo "== 3) Crear la base =="
# az postgres flexible-server db create -g "$RG" -s "$PG" -d "$DB"
az postgres flexible-server db list -g "$RG" -s "$PG" --query '[].name' -o tsv

echo "== 4) Parámetros del servidor (extensiones, PgBouncer, registro de consultas lentas) =="
# az postgres flexible-server parameter set -g "$RG" -s "$PG" -n azure.extensions --value "PG_STAT_STATEMENTS,PGCRYPTO,UUID-OSSP,VECTOR,PG_CRON"
# az postgres flexible-server parameter set -g "$RG" -s "$PG" -n pgbouncer.enabled --value true
# az postgres flexible-server parameter set -g "$RG" -s "$PG" -n log_min_duration_statement --value 500
az postgres flexible-server parameter show -g "$RG" -s "$PG" -n max_connections --query '{valor:value,defecto:defaultValue}' -o table
az postgres flexible-server parameter list -g "$RG" -s "$PG" --query "[?isConfigPendingRestart==\`true\`].{param:name,valor:value}" -o table 2>/dev/null || true

echo "== 5) Firewall (solo desarrollo con acceso público) =="
# az postgres flexible-server firewall-rule create -g "$RG" -n "$PG" --rule-name mi-ip --start-ip-address 203.0.113.10 --end-ip-address 203.0.113.10
az postgres flexible-server firewall-rule list -g "$RG" -n "$PG" -o table 2>/dev/null || true

echo "== 6) Escalar y reiniciar (provoca un corte breve) =="
# az postgres flexible-server update -g "$RG" -n "$PG" --sku-name Standard_D8ds_v5 --tier GeneralPurpose
# az postgres flexible-server restart -g "$RG" -n "$PG"
# Para ahorrar en desarrollo (se paga solo el almacenamiento; máx. 7 días parado):
# az postgres flexible-server stop -g "$RG" -n "$PG"
# az postgres flexible-server start -g "$RG" -n "$PG"

echo "== 7) Alta disponibilidad y prueba de conmutación (ventana de prueba) =="
# az postgres flexible-server update -g "$RG" -n "$PG" --high-availability ZoneRedundant --zone 1 --standby-zone 2
# az postgres flexible-server restart -g "$RG" -n "$PG" --failover Forced

echo "== 8) Réplica de lectura y promoción =="
# az postgres flexible-server replica create -g "$RG" --replica-name "$PG-lectura" --source-server "$PG"
az postgres flexible-server replica list -g "$RG" -n "$PG" -o table 2>/dev/null || true
# az postgres flexible-server replica promote -g "$RG" -n "$PG-lectura" --promote-mode standalone --promote-option planned

echo "== 9) Restaurar a un punto en el tiempo (crea OTRO servidor) =="
# az postgres flexible-server restore -g "$RG" -n "$PG-restaurado" --source-server "$PG" --restore-time "2026-10-16T14:30:00Z"

echo "== 10) Conectar con tu identidad de Entra (el token es la contraseña) =="
cat <<'PSQL'
export PGPASSWORD="$(az account get-access-token --resource-type oss-rdbms --query accessToken -o tsv)"
psql "host=$PG.postgres.database.azure.com port=5432 dbname=pedidos user=<tu usuario o grupo en Entra> sslmode=require"
# A través de PgBouncer (puerto 6432):
psql "host=$PG.postgres.database.azure.com port=6432 dbname=pedidos user=<tu usuario> sslmode=require"
# Ejecutar los scripts de ejemplo:
psql "host=... dbname=pedidos user=..." -f ejemplos/sql/01-roles-y-permisos.sql
PSQL

echo "== 11) Métricas rápidas =="
ID=$(az postgres flexible-server show -g "$RG" -n "$PG" --query id -o tsv)
for m in cpu_percent memory_percent storage_percent active_connections connections_failed; do
  echo "-- $m"
  az monitor metrics list --resource "$ID" --metric "$m" --interval PT5M --offset 1h --aggregation Maximum \
    --query 'value[0].timeseries[0].data[-3:].{hora:timeStamp,max:maximum}' -o table || true
done

echo "ok"
