#!/usr/bin/env bash
# Azure SQL Database por CLI: servidor solo-Entra, bases, red, copias, restauración, DR y consultas con sqlcmd -G.
# Ejecuta por secciones. Requiere: az login. Los parámetros varían por versión del CLI: revisa --help.
set -euo pipefail

RG=rg-estudio-azuresql
SQL=sql-modalima-XXXXXX             # salida "servidor" de Terraform (sin .database.windows.net)
DB=pedidos
LOC=eastus2
GRUPO_ADMIN_NOMBRE=DBAdmins
GRUPO_ADMIN_ID=00000000-0000-0000-0000-0000000000aa   # object id del grupo en Entra

echo "== 1) Servidor con SOLO Entra ID y TLS 1.2 =="
# az sql server create -g "$RG" -n "$SQL" -l "$LOC" \
#   --enable-ad-only-auth --external-admin-principal-type Group \
#   --external-admin-name "$GRUPO_ADMIN_NOMBRE" --external-admin-sid "$GRUPO_ADMIN_ID" \
#   --minimal-tls-version 1.2 --enable-public-network false
az sql server show -g "$RG" -n "$SQL" \
  --query '{fqdn:fullyQualifiedDomainName,tls:minimalTlsVersion,publico:publicNetworkAccess,estado:state}' -o table
az sql server ad-only-auth get -g "$RG" -n "$SQL" -o table

echo "== 2) Base serverless que se pausa tras 60 min =="
# az sql db create -g "$RG" -s "$SQL" -n "$DB" --edition GeneralPurpose --family Gen5 --capacity 2 \
#   --compute-model Serverless --auto-pause-delay 60 --min-capacity 0.5 --backup-storage-redundancy Local
az sql db show -g "$RG" -s "$SQL" -n "$DB" \
  --query '{sku:sku.name,estado:status,pausaMin:autoPauseDelay,zona:zoneRedundant,copias:currentBackupStorageRedundancy}' -o table

echo "== 3) Escalar la base (cambia de nivel con unos segundos de corte de conexiones) =="
# az sql db update -g "$RG" -s "$SQL" -n "$DB" --capacity 4

echo "== 4) Copias de seguridad: PITR y retención a largo plazo =="
az sql db audit-policy show -g "$RG" -s "$SQL" -n "$DB" -o table 2>/dev/null || true
# az sql db str-policy set -g "$RG" -s "$SQL" -n "$DB" --retention-days 14 --diffbackup-hours 12
# az sql db ltr-policy set -g "$RG" -s "$SQL" -n "$DB" --weekly-retention P4W --monthly-retention P12M --yearly-retention P5Y --week-of-year 1
az sql db ltr-backup list -l "$LOC" -s "$SQL" -d "$DB" -o table 2>/dev/null || true

echo "== 5) Restaurar a un punto en el tiempo (crea OTRA base; no pisa la original) =="
# az sql db restore -g "$RG" -s "$SQL" -n "$DB" --dest-name "${DB}-restaurada" --time "2026-10-16T14:30:00Z"
# Recuperar una base eliminada dentro de la retención:
az sql db list-deleted -g "$RG" -s "$SQL" -o table 2>/dev/null || true
# az sql db restore -g "$RG" -s "$SQL" -n "$DB" --dest-name "${DB}-recuperada" --deleted-time "<fecha de borrado>"

echo "== 6) Red: ni IP públicas ni 'servicios de Azure'; solo Private Endpoint =="
az sql server firewall-rule list -g "$RG" -s "$SQL" -o table 2>/dev/null || true
# az sql server update -g "$RG" -n "$SQL" --enable-public-network false
# Regla 0.0.0.0 = "Permitir servicios de Azure": NO debe existir
az sql server firewall-rule list -g "$RG" -s "$SQL" --query "[?startIpAddress=='0.0.0.0']" -o table 2>/dev/null || true
az sql server conn-policy show -g "$RG" -s "$SQL" -o table 2>/dev/null || true

echo "== 7) Seguridad: auditoría, Defender y TDE =="
az sql server audit-policy show -g "$RG" -n "$SQL" -o table 2>/dev/null || true
az sql db tde show -g "$RG" -s "$SQL" -d "$DB" -o table 2>/dev/null || true
az sql server tde-key show -g "$RG" -s "$SQL" -o table 2>/dev/null || true

echo "== 8) Recuperación ante desastres: grupo de conmutación por error =="
# az sql failover-group create -g "$RG" -s "$SQL" -n fg-modalima --partner-server sql-modalima-dr-XXXXXX \
#   --partner-resource-group "$RG" --add-db "$DB" --failover-policy Automatic --grace-period 1
# Probar la conmutación (haz esto en una ventana de prueba):
# az sql failover-group set-primary -g "$RG" -s sql-modalima-dr-XXXXXX -n fg-modalima

echo "== 9) Consultar con tu identidad de Entra (sqlcmd -G, sin contraseña) =="
cat <<'SQLCMD'
sqlcmd -S sql-modalima-XXXXXX.database.windows.net -d pedidos -G -N -C -Q "SELECT SUSER_SNAME() AS yo, DB_NAME() AS base"
sqlcmd -S sql-modalima-XXXXXX.database.windows.net -d pedidos -G -N -i ejemplos/sql/03-diagnostico.sql
# Ejecutar como usuario de una aplicación (token de la identidad administrada): solo desde un recurso Azure con esa identidad
SQLCMD

echo "== 10) Métricas rápidas =="
ID=$(az sql db show -g "$RG" -s "$SQL" -n "$DB" --query id -o tsv)
for m in cpu_percent storage_percent workers_percent connection_failed deadlock; do
  echo "-- $m"
  az monitor metrics list --resource "$ID" --metric "$m" --interval PT5M --offset 1h --aggregation Maximum \
    --query 'value[0].timeseries[0].data[-3:].{hora:timeStamp,max:maximum}' -o table || true
done

echo "ok"
